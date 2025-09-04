// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;


interface IBasisAsset {
    function mint(address recipient, uint256 amount) external;
}
