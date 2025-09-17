// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {IOracle} from "../interfaces/IOracle.sol";
import {IMasterOracle} from "../interfaces/IMasterOracle.sol";
import {Token} from "./Token.sol";

contract MockMasterOracle is IMasterOracle {

    mapping(address => uint256) lastPrice;
    mapping(address => address) twapOracle;
    address public  tokenAsked;

    function getLatestPrice(address _token) external view returns (uint256) {
        return lastPrice[_token];
    }

    function getTokenTWAP(address _token) external view returns (uint256) {
        return IOracle(twapOracle[_token]).consult(_token, 1e18);
    }


    function setLastPrice(address _token, uint256 _lastPrice) external {
        lastPrice[_token] = _lastPrice;
    }

    function setTwapOracle(address _token, address _twapOracle) external {
        twapOracle[_token] = _twapOracle;
    }

}