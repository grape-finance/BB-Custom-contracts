//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ITreasury {
    function epoch() external view returns (uint256);

    function nextEpochPoint() external view returns (uint256);

    function getFavorPrice() external view returns (uint256);
}
