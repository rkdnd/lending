pragma solidity ^0.8.13;
/*
    청산 방법 : getFCLiquidationList() 함수를 통해 현재 청산해야하는 (구입 시세보다 75% 이상 가격이 떨어진) 사용자들의 주소를 배열로 받아옵니다.
                사용자의 주소를 liquidate() 함수에 입력해 청산합니다.
*/

import "./ERC20.sol";
import "./DreamOracle.sol";
import "./dpsToken.sol";
import "./debtToken.sol";

interface ILending{
    function deposit(address tokenAddress, uint256 amount) external;
    function borrow(address tokenAddress, uint256 amount) external;
    function repay(address tokenAddress, uint256 amount) external;
    function liquidate(address user, address tokenAddress, uint256 amount) external;
    function withdraw(address tokenAddress, uint256 amount) external;
}

contract Lending is ILending, ERC20("GWLENDING", "GWL"){
    address ETHER;
    address USDC;
    dpsToken dpseth;
    dpsToken dpsusdc;
    debtToken debtusdc;
    address oracle;

    mapping(uint256 => address[]) borrowerMarketPrice;
    address[] FCLiquidationList;
    uint256[] marketPriceList;

    constructor(address _eth, address _usdc, address _oracle){
        ETHER = _eth;
        USDC = _usdc;

        dpseth = new dpsToken("deposited ETHER", "dpsETH");
        dpsusdc = new dpsToken("deposited USDC", "dpsUSDC");
        debtusdc = new debtToken("deptUSDC", "debtUSDC");

        oracle = _oracle;
    }

    function deposit(address tokenAddress, uint256 amount) external payable{
        require(tokenAddress == address(0) || tokenAddress == USDC);

        if(tokenAddress == address(0)){
            require(msg.value == amount);
            dpsToken(dpseth).mint(msg.sender, amount);
        }else{
            ERC20(tokenAddress).transferFrom(msg.sender, address(this), amount);
            dpsToken(dpsusdc).mint(msg.sender, amount);
        }
    }
    
    function withdraw1(address tokenAddress, uint256 amount) external{
        require(tokenAddress == address(0) || tokenAddress == USDC);

        if(tokenAddress == address(0)){
            dpsToken(dpseth).updateInterest(msg.sender);

            require(dpsToken(dpseth).balanceOf(msg.sender) >= amount);
            payable(msg.sender).transfer(amount);
            dpsToken(dpseth).burn(msg.sender, amount);
        }else{
            dpsToken(dpsusdc).updateInterest(msg.sender);
            
            require(dpsToken(dpseth).balanceOf(msg.sender) >= amount);
            ERC20(tokenAddress).transfer(msg.sender, amount);
            dpsToken(dpsusdc).burn(msg.sender, amount);
        }
    }

    function borrow(address tokenAddress, uint256 amount) external{
        require(tokenAddress == USDC);
        
        uint256 usdcPrice = DreamOracle(oracle).getPrice(address(USDC));
        uint256 etherPrice = DreamOracle(oracle).getPrice(address(ETHER));
        uint256 depositedBalance = dpsToken(dpseth).balanceOf(msg.sender);
        uint256 maxLTV = ((usdcPrice / etherPrice) * depositedBalance) / 2;
        require(maxLTV >= amount + debtToken(debtusdc).balanceOf(msg.sender));

        dpsToken(dpseth).burn(msg.sender, (amount * 2));

        debtToken(debtusdc).mint(msg.sender, amount);
        ERC20(tokenAddress).transfer(msg.sender, amount);
    }

    function repay(address tokenAddress, uint256 amount) external{
        require(tokenAddress == USDC);
        uint256 clientLoan = debtToken(debtusdc).balanceOf(msg.sender);

        debtToken(debtusdc).updateInterest(msg.sender);
        if(clientLoan > amount){
            ERC20(USDC).transferFrom(msg.sender, address(this), amount);
            debtToken(debtusdc).burn(msg.sender, amount);
        }else{
            ERC20(USDC).transferFrom(msg.sender, address(this), clientLoan);
            debtToken(debtusdc).burn(msg.sender, clientLoan);
            dpsToken(dpseth).clearLoan();
        }
    }
    // function liquidate(address user, address tokenAddress, uint256 amount) external{
    //     require(tokenAddress == USDC);
    //     require(amount <= ERC20(USDC).balanceOf(msg.sender), "InputToken overd own balance");
    //     require(USDCLoan[user].principal > 0, "request user doesn't have any loan");

    //     require(FCLiquiExistCheck(user) == true);

    //     (uint256 fee, uint256 blockTimestemp) = countFee(USDCLoan[user].welfare, USDCLoan[user].borrowTime);
    //     USDCLoan[user].welfare += fee;
    //     USDCLoan[user].borrowTime = blockTimestemp;

    //     require(amount >= USDCLoan[user].principal);
    //     ERC20(USDC)._transfer(msg.sender, address(this), USDCLoan[user].principal);
    //     ERC20(ETHER)._transfer(address(this), msg.sender, USDCLoan[user].principal);
    //     USDCLoan[user].welfare = 0;
    //     USDCLoan[user].principal = 0;
    //     delete FCLiquidationList[findArray(user)];

    //     _setTotalSupply();
    // }

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