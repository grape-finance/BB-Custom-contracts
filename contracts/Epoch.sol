
// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./libraries/HomoraMath.sol";

contract Epoch is Ownable {
    using SafeMath for uint256;

    // Approved users mapping
    mapping(address => bool) public isApprovedUser;

    // Epoch state variables
    uint256 private period;
    uint256 private startTime;
    uint256 private lastEpochTime;
    uint256 private epoch;

    // Events
    event ApprovedUserSet(address indexed user, bool allowed);
    event PeriodUpdated(uint256 newPeriod);
    event EpochUpdated(uint256 newEpoch);

    /* ========== CONSTRUCTOR ========== */

    constructor(
        uint256 _period,
        uint256 _startTime,
        uint256 _startEpoch
    ) Ownable(msg.sender) {
        period = _period;
        startTime = _startTime;
        epoch = _startEpoch;
        lastEpochTime = startTime.sub(period);
        isApprovedUser[msg.sender] = true;
    }

    /* ========== MODIFIERS ========== */

    modifier onlyApproved() {
        require(isApprovedUser[msg.sender] || msg.sender == owner(), "Epoch: caller not approved");
        _;
    }

    modifier checkStartTime {
        require(block.timestamp >= startTime, 'Epoch: not started yet');
        _;
    }

    modifier checkEpoch {
        uint256 _nextEpochPoint = nextEpochPoint();
        if (block.timestamp < _nextEpochPoint) {
            require(isApprovedUser[msg.sender] || msg.sender == owner(), 'Epoch: only approved users allowed for pre-epoch');
            _;
        } else {
            _;
            for (;;) {
                lastEpochTime = _nextEpochPoint;
                ++epoch;
                _nextEpochPoint = nextEpochPoint();
                if (block.timestamp < _nextEpochPoint) break;
            }
        }
    }

    /* ========== VIEW FUNCTIONS ========== */

    function getCurrentEpoch() public view returns (uint256) {
        return epoch;
    }

    function getPeriod() public view returns (uint256) {
        return period;
    }

    function getStartTime() public view returns (uint256) {
        return startTime;
    }

    function getLastEpochTime() public view returns (uint256) {
        return lastEpochTime;
    }

    function nextEpochPoint() public view returns (uint256) {
        return lastEpochTime.add(period);
    }

    /* ========== GOVERNANCE ========== */

    function setPeriod(uint256 _period) external onlyApproved {
        require(_period >= 15 minutes && _period <= 24 hours, '_period: out of range');
        period = _period;
        emit PeriodUpdated(_period);
    }

    function setEpoch(uint256 _epoch) external onlyApproved {
        epoch = _epoch;
        emit EpochUpdated(_epoch);
    }

    function setApprovedUser(address user, bool allowed) external onlyOwner {
        require(user != address(0), "Zero address not allowed");
        isApprovedUser[user] = allowed;
        emit ApprovedUserSet(user, allowed);
    }
}