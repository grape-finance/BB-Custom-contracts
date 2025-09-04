//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IFavorToken {
    function logBuy(address user, uint amount) external;

    function isTaxExempt(address user) external returns (bool);

    function treasury() external returns (address);

    function calculateTax(uint256 amount) external returns (uint256);
}