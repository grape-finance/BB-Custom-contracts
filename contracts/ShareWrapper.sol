// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract ShareWrapper {
    using SafeERC20 for IERC20;

    IERC20 public esteem;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 amount) public virtual {
        _totalSupply += amount;
        _balances[msg.sender] += amount;
        esteem.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public virtual {
        uint256 groveUserEsteem = _balances[msg.sender];
        require(groveUserEsteem >= amount, "Grove: withdraw request greater than staked amount");
        _totalSupply -= amount;
        _balances[msg.sender] = groveUserEsteem - amount;
        esteem.safeTransfer(msg.sender, amount);
    }
}
