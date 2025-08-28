// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface BBToken {
    function mint(address recipient, uint256 amount) external;

    function burn(uint256 amount) external;

    function burnFrom(address from, uint256 amount) external;

}