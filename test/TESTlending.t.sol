pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/ERC20.sol";
import "../src/Lending.sol";
import "../src/DreamOracle.sol";

contract MintableToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {

    }

    function mint(address receiver, uint256 value) public {
        super._mint(receiver, value);
    }
}

contract lending is Test {
    Lending lending;
    MintableToken ETHER;
    MintableToken USDOLLAR;
    DreamOracle oracle;

    function setUp() public {
        ETHER = new MintableToken("ETHER", "ETH");
        USDOLLAR = new MintableToken("USDOLLAR", "USDC");
        oracle = new DreamOracle();
        oracle.setPrice(address(USDOLLAR), 1000 ether);
        oracle.setPrice(address(ETHER), 1 ether);
        ETHER.mint(address(this), 500 ether);
        USDOLLAR.mint(address(this), 500 ether);
        lending = new Lending(address(ETHER), address(USDOLLAR), address(oracle));            
    }

    function testSimpleDeposit() public {
        lending.deposit(address(ETHER), 10 ether);
        require(lending.ETHTotalSupply() == 10 ether);
        lending.deposit(address(USDOLLAR), 10 ether);
        require(lending.USDCTotalSupply() == 10 ether);
        lending.deposit(address(USDOLLAR), 10 ether);
        require(lending.USDCTotalSupply() == 20 ether);
    }

    function testFailSimpleBorrow() public{
        lending.deposit(address(USDOLLAR), 100 ether);
        lending.borrow(address(ETHER), 120 ether);
        vm.expectRevert("InputToken overd own balance");

        lending.deposit(address(USDOLLAR), 10 ether);
        lending.borrow(address(ETHER), 100 ether);
        vm.expectRevert("not enough USDC balance");
    }

    function testSimpleRepay() public{
        lending.deposit(address(USDOLLAR), 500 ether);

        address actor1 = address(0xaa);
        require(ERC20(USDOLLAR).balanceOf(address(0xaa)) == 0);
        ETHER.mint(address(actor1), 1 ether);
        vm.prank(address(0xaa));
        lending.borrow(address(ETHER), 1 ether);
        require(ERC20(USDOLLAR).balanceOf(address(0xaa)) == 500 ether);
        
        vm.prank(address(0xaa));
        lending.repay(address(USDOLLAR), 500 ether);
        require(ERC20(USDOLLAR).balanceOf(address(0xaa)) == 0 ether);
        require(lending.getLoanState(address(0xaa)) == 0 ether);
    }

    function testFeeRepay() public{
        lending.deposit(address(USDOLLAR), 500 ether);
        address actor1 = address(0xaa);

        require(ERC20(USDOLLAR).balanceOf(address(0xaa)) == 0);
        ETHER.mint(address(actor1), 1 ether);
        vm.prank(address(0xaa));
        lending.borrow(address(ETHER), 1 ether);
        require(ERC20(USDOLLAR).balanceOf(address(0xaa)) == 500 ether);

        vm.warp(block.timestamp + 24 hours);
        vm.prank(address(0xaa));
        lending.repay(address(USDOLLAR), 50 ether);
        require(lending.getLoanState(address(0xaa)) == 500 ether);
    }

    function testFailSimpleWithdraw() public{
        address actor1 = address(0xaa);
        lending.deposit(address(USDOLLAR), 50 ether);
        lending.withdraw(address(USDOLLAR), 60 ether);
        vm.expectRevert("InputToken overd own balance");
    }

    function testSimpleWithdraw() public{
        lending.deposit(address(USDOLLAR), 50 ether);
        require(lending.USDCTotalSupply() == 50 ether);
        require(lending.getBalance(address(USDOLLAR)) == 50 ether);
        lending.withdraw(address(USDOLLAR), 50 ether);
        require(lending.USDCTotalSupply() == 0 ether);
    }

    function testCountFee() public{
        lending.deposit(address(USDOLLAR), 10 ether);
        require(lending.USDCTotalSupply() == 10 ether);
        require(lending.getBalance(address(USDOLLAR)) == 10 ether);
        vm.warp(block.timestamp + 48 hours);
        lending.withdraw(address(USDOLLAR), 5 ether);
        require(lending.getBalance(address(USDOLLAR)) == 7.1 ether);
    }

    address[] list;
    function testSimpleFCLiquidation() public {
        oracle.setPrice(address(USDOLLAR), 100 ether);
        oracle.setPrice(address(ETHER), 1 ether);

        ETHER.mint(address(this), 5000 ether);
        USDOLLAR.mint(address(this), 5000 ether);

        lending.deposit(address(USDOLLAR), 1000 ether);
        address actor1 = address(0xaa);

        ETHER.mint(address(0xaa), 5 ether);
        vm.prank(address(0xaa));
        lending.borrow(address(ETHER), 1 ether);
        oracle.setPrice(address(USDOLLAR), 72 ether);
        list = lending.getFCLiquidationList();
        require(list[0] == address(0xaa));
    }

    function testFCLiquidation() public {
        oracle.setPrice(address(USDOLLAR), 100 ether);
        oracle.setPrice(address(ETHER), 1 ether);

        ETHER.mint(address(this), 5000 ether);
        USDOLLAR.mint(address(this), 5000 ether);

        lending.deposit(address(USDOLLAR), 5000 ether);
        address actor1 = address(0xaa);
        address actor2 = address(0xbb);
        address actor3 = address(0xcc);
        address actor4 = address(0xdd);

        ETHER.mint(address(0xaa), 5 ether);
        vm.prank(address(0xaa));
        lending.borrow(address(ETHER), 5 ether);

        oracle.setPrice(address(USDOLLAR), 80 ether);
        ETHER.mint(address(0xbb), 5 ether);
        vm.prank(address(0xbb));
        lending.borrow(address(ETHER), 5 ether);

        oracle.setPrice(address(USDOLLAR), 15 ether);
        ETHER.mint(address(0xcc), 5 ether);
        vm.prank(address(0xcc));
        lending.borrow(address(ETHER), 5 ether);

        oracle.setPrice(address(USDOLLAR), 0.1 ether);
        ETHER.mint(address(0xdd), 5 ether);
        vm.prank(address(0xdd));
        lending.borrow(address(ETHER), 5 ether);
        
        list = lending.getFCLiquidationList();
        require(list[1] == address(0xbb));

        lending.liquidate(list[1], address(USDOLLAR), 100 ether);
        require(lending.getLoanState(address(0xbb)) == 0 ether);
    }
}