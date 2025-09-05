//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IOracle {
    function getLatestPrice(address _token) external view returns (uint256 amountOut);

    function getTokenTWAP(address _token) external view returns (uint256 updatedPrice);
}
