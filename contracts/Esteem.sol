// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";


contract Esteem is ERC20Burnable, Ownable {

    mapping(address => bool) public isMinter;

    event MinterAdded(address indexed minter);
    event MinterRemoved(address indexed minter);


    modifier onlyMinter() {
        require(isMinter[_msgSender()], "OnlyMinter: caller is not a minter");
        _;
    }

    constructor() ERC20("Esteem Token", "ESTEEM") Ownable(msg.sender){}

    function mint(address recipient_, uint256 amount_) public onlyMinter {
        _mint(recipient_, amount_);
    }

    function addMinter(address account) external onlyOwner {
        isMinter[account] = true;
        emit MinterAdded(account);
    }

    function removeMinter(address account) external onlyOwner {
        isMinter[account] = false;
        emit MinterRemoved(account);
    }

}