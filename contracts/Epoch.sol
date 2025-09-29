
// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import {EpochKeeper} from "./EpochKeeper.sol";

// Epoch is abstract class for thise who wants to keep track on current epoch and keep  and update some
// state based on epoch
// simple use classes can just use epoch keeper to have a notion of current epoch
abstract contract Epoch is Ownable2Step {

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


    // check whether new epoch is started,  if not -  just silently refuse doing anything
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