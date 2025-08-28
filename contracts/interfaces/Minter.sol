// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

interface Minter {

    function esteemRate() external view returns (uint256);

    function getFavorPrice(address _favorToken) external view returns (uint256 updatedPrice);

    function latestETHPrice() external view returns (uint256);

}
