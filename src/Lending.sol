pragma solidity ^0.8.13;
/*
    청산 방법 : getFCLiquidationList() 함수를 통해 현재 청산해야하는 (구입 시세보다 75% 이상 가격이 떨어진) 사용자들의 주소를 배열로 받아옵니다.
                사용자의 주소를 liquidate() 함수에 입력해 청산합니다.
*/

import "./ERC20.sol";
import "./DreamOracle.sol";

interface ILending{
    function deposit(address tokenAddress, uint256 amount) external;
    function borrow(address tokenAddress, uint256 amount) external;
    function repay(address tokenAddress, uint256 amount) external;
    function liquidate(address user, address tokenAddress, uint256 amount) external;
    function withdraw(address tokenAddress, uint256 amount) external;
}

contract Lending is ILending, ERC20("GWLENDING", "GWL"){
    address oracle;
    address ETHER;
    address USDC;

    uint256 public ETHTotalSupply;
    uint256 public USDCTotalSupply;

    mapping(uint256 => address[]) borrowerMarketPrice;
    address[] FCLiquidationList;
    uint256[] marketPriceList;

    mapping(address => amountState) internal ETHBalance;
    mapping(address => amountState) internal USDCBalance;
    mapping(address => loanState) internal USDCLoan;
    struct amountState{
        uint256 amount;
        uint256 borrowTime;
    }
    struct loanState{
        uint256 principal;
        uint256 welfare;
        uint256 borrowTime;
    }

    constructor(address _eth, address _usdc, address _oracle){
        ETHER = _eth;
        USDC = _usdc;
        oracle = _oracle;
    }

    function getBalance(address tokenAddress) public returns(uint256 amount){
        if(keccak256(abi.encodePacked((ERC20(tokenAddress).symbol()))) == keccak256(abi.encodePacked(("ETH"))))
            amount = ETHBalance[msg.sender].amount;
        else if(keccak256(abi.encodePacked((ERC20(tokenAddress).symbol()))) == keccak256(abi.encodePacked(("USDC"))))
            amount = USDCBalance[msg.sender].amount;
    }

    function getLoanState(address user) public returns(uint256 amount){
        amount = USDCLoan[user].welfare;
    }

    function _setTotalSupply() internal {
        ETHTotalSupply = ERC20(ETHER).balanceOf(address(this));
        USDCTotalSupply = ERC20(USDC).balanceOf(address(this));
    }

    function _setBalance(address tokenAddress, address sender, uint256 amount) internal {
        if(keccak256(abi.encodePacked((ERC20(tokenAddress).symbol()))) == keccak256(abi.encodePacked(("ETH"))))
            ETHBalance[sender] = amountState(amount, block.timestamp);
        else if(keccak256(abi.encodePacked((ERC20(tokenAddress).symbol()))) == keccak256(abi.encodePacked(("USDC"))))
            USDCBalance[sender] = amountState(amount, block.timestamp);
    }

    function countFee(uint256 amount, uint256 timestemp) internal returns (uint256 fee, uint256 blockTimestemp){
        blockTimestemp = block.timestamp;
        uint256 dayCount = (blockTimestemp - timestemp) / 24 hours;
        uint256 remainDayCount = (blockTimestemp - timestemp) % 24 hours;
        uint256 beforeCal = amount;

        for(uint256 i = 0; i < dayCount; i++){
            amount += amount / 10;
        }
        blockTimestemp += remainDayCount;
        fee = amount - beforeCal;
    }

    function deposit(address tokenAddress, uint256 amount) override public{
        require(amount <= ERC20(tokenAddress).balanceOf(msg.sender), "InputToken overd own balance");
        ERC20(tokenAddress)._transfer(msg.sender, address(this), amount);

        _setBalance(tokenAddress, msg.sender, amount);
        _setTotalSupply();
    }

    function borrow(address tokenAddress, uint256 amount) external{
        require(keccak256(abi.encodePacked((ERC20(tokenAddress).symbol()))) == keccak256(abi.encodePacked(("ETH"))));
        require(amount <= ERC20(ETHER).balanceOf(msg.sender), "InputToken overd own balance");

        amount = amount / DreamOracle(oracle).getPrice(address(ETHER));
        uint256 etherPrice = DreamOracle(oracle).getPrice(address(USDC));
        uint256 borrowAmount = (amount * etherPrice) * 5 / 10;
        require(borrowAmount <= USDCTotalSupply, "not enough USDC balance");

        ERC20(ETHER)._transfer(msg.sender, address(this), amount);
        USDCLoan[msg.sender] = loanState(amount, borrowAmount, block.timestamp);
        ERC20(USDC)._transfer(address(this), msg.sender, borrowAmount);
        
        borrowerMarketPrice[etherPrice].push(msg.sender);
        marketPriceList.push(etherPrice);
        marketPriceList = sort(marketPriceList);
        _setTotalSupply();
    }

    function repay(address tokenAddress, uint256 amount) external{
        require(keccak256(abi.encodePacked((ERC20(tokenAddress).symbol()))) == keccak256(abi.encodePacked(("USDC"))));
        require(amount <= ERC20(USDC).balanceOf(msg.sender), "InputToken overd own balance");

        (uint256 fee, uint256 blockTimestemp) = countFee(USDCLoan[msg.sender].welfare, USDCLoan[msg.sender].borrowTime);
        USDCLoan[msg.sender].welfare += fee;
        USDCLoan[msg.sender].borrowTime = blockTimestemp;

        if(USDCLoan[msg.sender].welfare > amount){
            USDCLoan[msg.sender].welfare -= amount;
            ERC20(USDC)._transfer(msg.sender, address(this), amount);
        }else{
            ERC20(USDC)._transfer(msg.sender, address(this), USDCLoan[msg.sender].welfare);
            ERC20(ETHER)._transfer(address(this), msg.sender, USDCLoan[msg.sender].principal);
            USDCLoan[msg.sender].welfare = 0;
            USDCLoan[msg.sender].principal = 0;
        }

        _setTotalSupply();
    }
    function liquidate(address user, address tokenAddress, uint256 amount) external{
        require(keccak256(abi.encodePacked((ERC20(tokenAddress).symbol()))) == keccak256(abi.encodePacked(("USDC"))));
        require(amount <= ERC20(USDC).balanceOf(msg.sender), "InputToken overd own balance");
        require(USDCLoan[user].principal > 0, "request user doesn't have any loan");

        require(FCLiquiExistCheck(user) == true);

        (uint256 fee, uint256 blockTimestemp) = countFee(USDCLoan[user].welfare, USDCLoan[user].borrowTime);
        USDCLoan[user].welfare += fee;
        USDCLoan[user].borrowTime = blockTimestemp;

        require(amount >= USDCLoan[user].principal);
        ERC20(USDC)._transfer(msg.sender, address(this), USDCLoan[user].principal);
        ERC20(ETHER)._transfer(address(this), msg.sender, USDCLoan[user].principal);
        USDCLoan[user].welfare = 0;
        USDCLoan[user].principal = 0;
        delete FCLiquidationList[findArray(user)];

        _setTotalSupply();
    }

    function updateFCLiquidationList() internal{
        uint256 etherPrice = DreamOracle(oracle).getPrice(address(USDC));

        for(uint i = 0; i < marketPriceList.length; i++){
            if((marketPriceList[i] * 75 / 100) >= etherPrice){
                for(uint k = 0; k < borrowerMarketPrice[marketPriceList[i]].length; k++)
                    FCLiquidationList.push(address(borrowerMarketPrice[marketPriceList[i]][k]));
            }
        }
    }

    function getFCLiquidationList() public returns(address[] memory list){
        updateFCLiquidationList();
        list= FCLiquidationList;
    }

    function withdraw(address tokenAddress, uint256 amount) external{
        if(keccak256(abi.encodePacked((ERC20(tokenAddress).symbol()))) == keccak256(abi.encodePacked(("ETH")))){
            (uint256 fee, uint256 blockTimestemp) = countFee(ETHBalance[msg.sender].amount, ETHBalance[msg.sender].borrowTime);
            ETHBalance[msg.sender].amount += fee;
            ETHBalance[msg.sender].borrowTime = blockTimestemp;

            require(amount <= ETHBalance[msg.sender].amount, "InputToken overd own balance");
            ETHBalance[msg.sender].amount -= amount;}
        else if(keccak256(abi.encodePacked((ERC20(tokenAddress).symbol()))) == keccak256(abi.encodePacked(("USDC")))){
            (uint256 fee, uint256 blockTimestemp) = countFee(USDCBalance[msg.sender].amount, USDCBalance[msg.sender].borrowTime);
            USDCBalance[msg.sender].amount += fee;
            USDCBalance[msg.sender].borrowTime = blockTimestemp;

            require(amount <= USDCBalance[msg.sender].amount, "InputToken overd own balance");
            USDCBalance[msg.sender].amount -= amount;}


        ERC20(tokenAddress)._transfer(address(this), msg.sender, (amount));
        _setTotalSupply();
    }

    function quickSort(uint[] memory arr, int left, int right) internal pure {
        int i = left;
        int j = right;
        if (i == j) return;
        uint pivot = arr[uint(left + (right - left) / 2)];
        while (i <= j) {
            while (arr[uint(i)] < pivot) i++;
            while (pivot < arr[uint(j)]) j--;
            if (i <= j) {
                (arr[uint(i)], arr[uint(j)]) = (arr[uint(j)], arr[uint(i)]);
                i++;
                j--;
            }
        }
        if (left < j)
            quickSort(arr, left, j);
        if (i < right)
            quickSort(arr, i, right);
    }

    function sort(uint[] memory data) public pure returns (uint[] memory) {
        quickSort(data, int(0), int(data.length - 1));
        return data;
    }

    function FCLiquiExistCheck(address user) public view returns (bool) {
        for (uint i = 0; i < FCLiquidationList.length; i++) {
            if (FCLiquidationList[i] == user) {
                return true;
            }
        }

        return false;
    }

    function findArray(address user) public returns (uint i){
        for (uint i = 0; i < FCLiquidationList.length; i++) {
            if (FCLiquidationList[i] == user) {
                return i;
            }
        }
    }

}