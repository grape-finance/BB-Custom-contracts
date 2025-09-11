// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/ITreasury.sol";


contract ShareWrapper {
    using SafeERC20 for IERC20;

    IERC20 public esteem;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 amount) public virtual {
        _totalSupply += amount;
        _balances[msg.sender] += amount;
        esteem.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public virtual {
        uint256 groveUserEsteem = _balances[msg.sender];
        require(groveUserEsteem >= amount, "Grove: withdraw request greater than staked amount");
        _totalSupply -= amount;
        _balances[msg.sender] = groveUserEsteem - amount;
        esteem.safeTransfer(msg.sender, amount);
    }
}

contract Staking is ShareWrapper, Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    uint256 public constant MAX_HISTORY = 50000;
    uint256 public historyStart;
    uint256 public historyEnd;

    struct GroveSeat {
        uint256 lastSnapshotIndex;
        uint256 rewardEarned;
    }

    struct GroveSnapshot {
        uint256 time;
        uint256 rewardReceived;
        uint256 rewardPerShare;
    }

    bool public initialized = false;

    IERC20 public favor;
    ITreasury public treasury;

    mapping(uint256 => GroveSnapshot) public groveHistory;
    mapping(address => GroveSeat) public grovers;

    address public treasuryOperator;

    event Initialized(address indexed executor, uint256 at);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardAdded(address indexed user, uint256 reward);
    event TreasuryOperatorUpdated(address indexed newOperator);
    event RecoveredUnsupportedToken(address indexed token, address indexed to, uint256 amount);
    event ContractPaused(address indexed admin);
    event ContractUnpaused(address indexed admin);

    modifier groveUserExists {
        require(balanceOf(msg.sender) > 0, "Grove: The user does not exist");
        _;
    }

    modifier updateReward(address groveUser) {
        if (groveUser != address(0)) {
            GroveSeat storage seat = grovers[groveUser];
            seat.rewardEarned = earned(groveUser);
            seat.lastSnapshotIndex  = latestSnapshotIndex();
        }
        _;
    }

    modifier notInitialized {
        require(!initialized, "Grove: already initialized");
        _;
    }

    constructor(address _owner)  Ownable(_owner)
    {}

    function initialize(
        IERC20 _favor,
        IERC20 _esteem,
        ITreasury _treasury
    ) public notInitialized onlyOwner {
        require(address(_favor) != address(0), "Invalid Favor address");
        require(address(_esteem) != address(0), "Invalid Esteem address");
        require(address(_treasury) != address(0), "Invalid Treasury address");

        favor = _favor;
        esteem = _esteem;
        treasury = _treasury;
        treasuryOperator = address(_treasury);

        GroveSnapshot memory genesis = GroveSnapshot({ time: block.timestamp, rewardReceived: 0, rewardPerShare: 0 });
        groveHistory[0] = genesis;
        historyStart = 0;
        historyEnd = 0;

        initialized = true;
        emit Initialized(msg.sender, block.timestamp);
    }

    function latestSnapshotIndex() public view returns (uint256) {
        return historyEnd;
    }

    function getLatestSnapshot() internal view returns (GroveSnapshot memory) {
        return groveHistory[historyEnd];
    }

    function getLastSnapshotOf(address user) internal view returns (GroveSnapshot storage) {
        uint256 idx = grovers[user].lastSnapshotIndex;
        if (idx < historyStart) { idx = historyStart; }
        return groveHistory[idx];
    }

    function epoch() external view returns (uint256) {
        return treasury.epoch();
    }

    function nextEpochPoint() external view returns (uint256) {
        return treasury.nextEpochPoint();
    }

    function getFavorPrice() external view returns (uint256) {
        return treasury.getFavorPrice();
    }

    function rewardPerShare() public view returns (uint256) {
        return getLatestSnapshot().rewardPerShare;
    }

    function earned(address groveUser) public view returns (uint256) {
        uint256 latestRPS = getLatestSnapshot().rewardPerShare;
        uint256 storedRPS = getLastSnapshotOf(groveUser).rewardPerShare;

        return (balanceOf(groveUser) * (latestRPS - storedRPS)) / 1e18 + grovers[groveUser].rewardEarned;
    }

    function stake(uint256 amount) public override nonReentrant updateReward(msg.sender) whenNotPaused {
        require(amount > 0, "Grove: Cannot stake 0");
        super.stake(amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public override nonReentrant groveUserExists updateReward(msg.sender) whenNotPaused {
        require(amount > 0, "Grove: Cannot withdraw 0");
        claimReward();
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
    }

    function claimReward() public updateReward(msg.sender) {
        uint256 reward = grovers[msg.sender].rewardEarned;
        if (reward > 0) {
            grovers[msg.sender].rewardEarned = 0;
            favor.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function allocateSeigniorage(uint256 amount) external nonReentrant whenNotPaused {
        require(msg.sender == owner() || msg.sender == treasuryOperator, "Not authorized");
        require(amount > 0, "Grove: Cannot allocate 0");
        require(totalSupply() > 0, "Grove: Cannot allocate when totalSupply is 0");

        // Create & add new snapshot
        uint256 prevRPS = getLatestSnapshot().rewardPerShare;
        uint256 nextRPS = prevRPS + ((amount * 1e18) / totalSupply());

        historyEnd += 1;
        groveHistory[historyEnd] = GroveSnapshot({ time: block.timestamp, rewardReceived: amount, rewardPerShare: nextRPS });

        if (historyEnd - historyStart + 1 > MAX_HISTORY) {
            delete groveHistory[historyStart];
            historyStart += 1;
        }

        favor.safeTransferFrom(msg.sender, address(this), amount);
        emit RewardAdded(msg.sender, amount);
    }

    function setTreasuryOperator(address _treasuryOperator) external onlyOwner {
        require(_treasuryOperator != address(0), "Grove: zero address");
        treasuryOperator = _treasuryOperator;
        emit TreasuryOperatorUpdated(_treasuryOperator);
    }

    function governanceRecoverUnsupported(IERC20 _token, uint256 _amount, address _to) external onlyOwner {
        require(address(_token) != address(favor), "Cannot remove FAVOR tokens");
        require(address(_token) != address(esteem), "Cannot remove ESTEEM tokens");
        _token.safeTransfer(_to, _amount);
        emit RecoveredUnsupportedToken(address(_token), _to, _amount);
    }

    function pause() external onlyOwner {
        _pause();
        emit ContractPaused(msg.sender);
    }

    function unpause() external onlyOwner {
        _unpause();
        emit ContractUnpaused(msg.sender);
    }
}