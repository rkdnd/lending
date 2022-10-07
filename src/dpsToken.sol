// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './ERC20.sol';

contract dpsToken is ERC20{
    address private owner;
    mapping(address => uint256) timestamp;
    mapping(address => uint256) principal;
    constructor(string memory name, string memory symbol) ERC20(name, symbol){
        owner = msg.sender;
    }

    modifier onlyOwner(){
        require(msg.sender == owner);
        _;
    }

    function mint(address account, uint256 amount) public onlyOwner{
        if(timestamp[account] == 0)
            timestamp[account] = block.timestamp;
        else
            updateInterest(account);

        principal[account] += amount;
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external onlyOwner{
        _burn(account, amount);
        updateInterest(account);
    }

    function updateInterest(address account) public {
        uint256 blockTimestemp = block.timestamp;
        uint256 dayCount = (timestamp[account] - blockTimestemp) / 24 hours;
        uint256 remainDayCount = (timestamp[account] - blockTimestemp) % 24 hours;
        
        uint256 interestBalance = balanceOf(account);
        for(uint256 i = 0; i < dayCount; i++){
            interestBalance += interestBalance / 1000;
        }

        timestamp[account] = blockTimestemp - remainDayCount;
        _mint(account, (interestBalance - balanceOf(account)));
    }

    function clearLoan(address account) external onlyOwner{
        mint(account, (principal[account] - balanceOf(account)));
    }
}