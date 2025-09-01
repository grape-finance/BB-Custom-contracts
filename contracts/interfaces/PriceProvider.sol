// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

interface PriceProvider {
    function esteemRate() external view returns (uint256);
    function getLatestTokenPrice(address token) external view returns (uint256);
}
