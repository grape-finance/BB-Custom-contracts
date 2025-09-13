// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {IMasterOracle} from "../interfaces/IMasterOracle.sol";
import {Token} from "./Token.sol";

contract MockMasterOracle is IMasterOracle {

    mapping(address => uint256) lastPrice;
    mapping(address => uint256) tokenTwap;
    address public  tokenAsked;

    function getLatestPrice(address _token) external view returns (uint256) {
        return lastPrice[_token];
    }

    function getTokenTWAP(address _token) external view returns (uint256) {
        return tokenTwap[_token];
    }


    function setLastPrice(address _token, uint256 _lastPrice) external {
        lastPrice[_token] = _lastPrice;
    }

    function setTokenTwap(address _token, uint256 _tokenTwap) external {
        tokenTwap[_token] = _tokenTwap;
    }
}
