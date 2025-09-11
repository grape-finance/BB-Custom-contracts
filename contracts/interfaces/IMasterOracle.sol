//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;


//  TODO:     oracles ought to deliver Q112  prices,   also  uint224
interface IMasterOracle {
    function getLatestPrice(address _token) external view returns (uint256);
    function getTokenTWAP(address _token) external view returns (uint256);
}
