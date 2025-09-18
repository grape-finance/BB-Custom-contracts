// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title EpochKeeper
 * @dev This contract handles an epoch system where the epoch increments automatically every set period.
 * Epochs are based on a global start time, and the current epoch is determined by time elapsed.
 */
contract EpochKeeper is Ownable {

    /// @notice The timestamp when the epoch system started.
    uint256 public immutable epochStartTime;

    /// @notice The duration of each epoch in seconds. In this case, one day (86400 seconds).
    uint256 public epochDuration;

    /**
     * @dev Initializes the contract with a start time and sets the epoch duration.
     * @param _epochDuration Duration of one epoch in seconds, e.g., 86400 for one day.
     */
    constructor(uint256 _genesis, uint256 _epochDuration, address _owner)
    Ownable(_owner)
    {
        require(_epochDuration > 0, "zero epoch length");
        require(_genesis < block.timestamp, "genesis lies in future");
        epochStartTime = _genesis;
        epochDuration = _epochDuration;
    }


    function setEpochDuration(uint256 _epochDuration) public onlyOwner {
        epochDuration = _epochDuration;
    }
    /**
      * @notice Returns the current epoch number based on the elapsed time.
     * @dev The epoch number increments by 1 every `epochDuration` seconds.
     * @return uint256 The current epoch number.
     */
    function currentEpoch() public view returns (uint256) {
        return uint256((block.timestamp - epochStartTime) / epochDuration);
    }

    function currentEpochBoundary() public view returns (uint256 current_, uint256 from_, uint256 to_) {
        uint256 elapsed = block.timestamp - epochStartTime;
        current_ = elapsed / epochDuration;
        from_ = epochStartTime + current_ * epochDuration;
        to_ = from_ + epochDuration;
    }
}
