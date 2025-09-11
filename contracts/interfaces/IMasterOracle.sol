//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMasterOracle {
    function getLatestPrice(address _token) external view returns (uint256);
    function getTokenTWAP(address _token) external view returns (uint256);
}
