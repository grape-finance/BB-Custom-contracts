
// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import {EpochKeeper} from "./EpochKeeper.sol";

abstract contract Epoch is Ownable {

    // Approved users mapping
    mapping(address => bool) public isApprovedUser;

    EpochKeeper public  keeper;
    uint256 public currentEpoch;
    uint256 public activeEpochStart;
    uint256  public activeEpochEnd;

    // Events
    event ApprovedUserSet(address indexed user, bool allowed);

    /* ========== CONSTRUCTOR ========== */

    constructor(
        EpochKeeper _keeper,
        address _owner
    ) Ownable(_owner) {
        keeper = _keeper;
        _updateEpoch();
    }

    /* ========== MODIFIERS ========== */

    modifier onlyApproved() {
        require(isApprovedUser[msg.sender] || msg.sender == owner(), "Epoch: caller not approved");
        _;
    }

    //  TODO: not really useful
    modifier checkStartTime {
        require(block.timestamp >= keeper.epochStartTime(), 'Epoch: not started yet');
        _;
    }

    // check whether new epoch is started,  if not -  just silently refuse doing enything
    modifier checkEpoch {
        if (currentEpoch < keeper.currentEpoch()) {
            _;
        }
    }

    /* ========== VIEW FUNCTIONS ========== */

    function getCurrentEpoch() public view returns (uint256) {
        return keeper.currentEpoch();
    }

    function getPeriod() public view returns (uint256) {
        return keeper.epochDuration();
    }

    function getStartTime() public view returns (uint256) {
        return keeper.epochStartTime();
    }

    function nextEpochPoint() public view returns (uint256) {
        (,,uint256 to) = keeper.currentEpochBoundary();
        return to;
    }


    function setApprovedUser(address user, bool allowed) external onlyOwner {
        require(user != address(0), "Zero address not allowed");
        isApprovedUser[user] = allowed;
        emit ApprovedUserSet(user, allowed);
    }


    function _updateEpoch() internal {
        (uint256 e_, uint256 f_,  uint256 t_) = keeper.currentEpochBoundary();
        currentEpoch = e_;
        activeEpochStart = f_;
        activeEpochEnd = t_;
    }
}