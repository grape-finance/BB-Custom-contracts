//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
interface IFavorToken2 {
    function logBuy(address user, uint amount) external;
    function turnOnTax() external;
    function turnOffTax() external;
}