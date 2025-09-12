// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import "./interfaces/IOracle.sol";
import "./interfaces/IBasisAsset.sol";
import "./interfaces/IGrove.sol";


contract FavorTreasury is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    uint256 public constant PERIOD = 1 hours;
    uint256 public constant BASIS_DIVISOR = 100000; // 100%

    bool public initialized = false;

    uint256 public startTime;
    uint256 public epoch = 0;

    /* Addresses and LPs to exclude from supply calculation */ 
    address[] public excludedAddresses;
    address[] public lpPairsToExclude;
    mapping(address => bool) public excludedFromTotalSupply;
    mapping(address => bool) public isLpPairToExclude;

    address public favor;

    address public grove;
    address public favorOracle;

    uint256 public lastEpochCirculatingSupply; // 0 for the first run
    uint256 public maxSupplyExpansionPercent = 3000; // 3%
    uint256 public minSupplyExpansionPercent = 1; // 0.001%

    address public daoFund;
    uint256 public daoFundSharedPercent;

    event Initialized(address indexed executor, uint256 at);
    event GroveFunded(uint256 timestamp, uint256 seigniorage);
    event DaoFundFunded(uint256 timestamp, uint256 seigniorage);
    event GroveUpdated(address indexed newGrove);
    event FavorOracleUpdated(address indexed newOracle);
    event MaxSupplyExpansionPercentUpdated(uint256 newMaxExpansionPercent);
    event MinSupplyExpansionPercentUpdated(uint256 newMinExpansionPercent);
    event DaoFundUpdated(address indexed daoFund, uint256 daoFundSharedPercent);
    event ContractPaused(address indexed admin);
    event ContractUnpaused(address indexed admin);
    event ExcludedAddressAdded(address indexed excludedAddress);
    event ExcludedAddressRemoved(address indexed excludedAddress);
    event LpPairToExcludeAdded(address indexed pair);
    event LpPairToExcludeRemoved(address indexed pair);
    event RecoveredUnsupportedToken(address indexed token, address indexed to, uint256 amount);


    constructor(address _owner)  Ownable(_owner)
    {}

    modifier checkCondition {
        require(block.timestamp >= startTime, "Treasury: not started yet");
        _;
    }

    modifier checkEpoch {
        require(block.timestamp >= nextEpochPoint(), "Treasury: not opened yet");
        _;

        epoch = epoch + 1;
    }

    modifier notInitialized {
        require(!initialized, "Treasury: already initialized");
        _;
    }

    function isInitialized() public view returns (bool) {
        return initialized;
    }

    function nextEpochPoint() public view returns (uint256) {
        return startTime + (epoch * PERIOD);
    }

    function getAddressesExcluded() external view returns (address[] memory) {
        return excludedAddresses;
    }

    function getLpPairsExcluded() external view returns (address[] memory) {
        return lpPairsToExclude;
    }

    function getFavorPrice() public view returns (uint256 favorPrice) {
        try IOracle(favorOracle).consult(favor, 1e18) returns (uint256 price) {
            return price;
        } catch {
            revert("Treasury: failed to consult FAVOR price from the oracle");
        }
    }

    /// @notice Returns rolling TWAP price which is more likely to be prone to short term price fluctuations. Only used on UI for informational purposes.
    function getFavorUpdatedPrice() public view returns (uint256 _favorPrice) {
        try IOracle(favorOracle).twap(favor, 1e18) returns (uint256 price) {
            return price;
        } catch {
            revert("Treasury: failed to consult FAVOR price from the oracle");
        }
    }

    function initialize(
        address _favor,
        address _favorOracle,
        address _grove,
        uint256 _startTime
    ) public notInitialized onlyOwner {
        require(_favor != address(0), "Invalid Favor address");
        require(_favorOracle != address(0), "Invalid Oracle address");
        require(_grove != address(0), "Invalid Grove address");
        require(_startTime > block.timestamp, "Must start in future");

        favor = _favor;
        favorOracle = _favorOracle;
        grove = _grove;
        startTime = _startTime;

        initialized = true;
        emit Initialized(msg.sender, block.timestamp);
    }

    function setGrove(address _grove) external onlyOwner {
        require(_grove != address(0), "Invalid Grove address");
        grove = _grove;
        emit GroveUpdated(_grove);
    }

    function setFavorOracle(address _favorOracle) external onlyOwner {
        require(_favorOracle != address(0), "Invalid Oracle address");
        favorOracle = _favorOracle;
        emit FavorOracleUpdated(_favorOracle);
    }

    function setMaxSupplyExpansionPercents(uint256 _maxSupplyExpansionPercent) external onlyOwner {
        require(_maxSupplyExpansionPercent >= 1 && _maxSupplyExpansionPercent <= 10000, "_maxSupplyExpansionPercent: out of range"); // [0.001%, 10%]
        require(_maxSupplyExpansionPercent > minSupplyExpansionPercent, "max must be larger than min");
        maxSupplyExpansionPercent = _maxSupplyExpansionPercent;
        emit MaxSupplyExpansionPercentUpdated(_maxSupplyExpansionPercent);
    }

    function setMinSupplyExpansionPercents(uint256 _minSupplyExpansionPercent) external onlyOwner {
        require(_minSupplyExpansionPercent >= 1 && _minSupplyExpansionPercent <= 10000, "_minSupplyExpansionPercent: out of range"); // [0.001%, 10%]
        require(_minSupplyExpansionPercent < maxSupplyExpansionPercent, "min must be smaller than max");
        minSupplyExpansionPercent = _minSupplyExpansionPercent;
        emit MinSupplyExpansionPercentUpdated(_minSupplyExpansionPercent);
    }

    /// @dev Add addresses to an array to be excluded in Favor supply calculations for each epochs mints
    function addExcludedAddress(address _address) external onlyOwner {
        require(_address != address(0), "Cannot exclude zero address");
        require(!excludedFromTotalSupply[_address], "Address already excluded");
        
        excludedFromTotalSupply[_address] = true;
        excludedAddresses.push(_address);

        emit ExcludedAddressAdded(_address);
    }
    
    function removeExcludedAddress(address _address) external onlyOwner {
        require(excludedFromTotalSupply[_address], "Address not excluded");
        
        excludedFromTotalSupply[_address] = false;
        
        // Remove from array
        uint256 n = excludedAddresses.length;
        for (uint256 i = 0; i < n; i++) {
            if (excludedAddresses[i] == _address) {
                excludedAddresses[i] = excludedAddresses[n - 1];
                excludedAddresses.pop();
                break;
            }
        }
        
        emit ExcludedAddressRemoved(_address);
    }

    /// @dev Add LP pairs to an array to have their Favor tokens excluded in Favor supply calculations for each epochs mints
    /// @notice Used to exclude Favor from the LP cushion and FAVOR/FAVOR LPs the treasury holds
    function addLpPairToExclude(address pair) external onlyOwner {
        require(pair != address(0), "Zero pair");
        require(!isLpPairToExclude[pair], "Pair already added");

        address t0 = IUniswapV2Pair(pair).token0();
        address t1 = IUniswapV2Pair(pair).token1();
        require(t0 == favor || t1 == favor, "Pair missing FAVOR");

        isLpPairToExclude[pair] = true;
        lpPairsToExclude.push(pair);

        emit LpPairToExcludeAdded(pair);
    }

    function removeLpPairToExclude(address pair) external onlyOwner {
        require(isLpPairToExclude[pair], "Pair not present");
        isLpPairToExclude[pair] = false;

        // Remove from array
        uint256 n = lpPairsToExclude.length;
        for (uint256 i = 0; i < n; i++) {
            if (lpPairsToExclude[i] == pair) {
                lpPairsToExclude[i] = lpPairsToExclude[n - 1];
                lpPairsToExclude.pop();
                break;
            }
        }

        emit LpPairToExcludeRemoved(pair);
    }
    

     /// @notice Gas intensive if many addresses are added to the list, planned usage is for ~10 protocol wallets/contracts & 2 LPs at most
    function getFavorCirculatingSupply() public view returns (uint256) {
        uint256 totalSupply = IERC20(favor).totalSupply();

        // Loose Favor balances of excluded addresses
        uint256 balanceExcluded = 0;
        uint256 excludedLen = excludedAddresses.length;
        for (uint256 i = 0; i < excludedLen; i++) {
            balanceExcluded += IERC20(favor).balanceOf(excludedAddresses[i]);
        }

        // Favor in LP tokens held by excluded addresses
        uint256 favorFromLpHeldByExcluded = 0;
        uint256 pairsLen = lpPairsToExclude.length;

        // Loop through LP pairs excluded and calculate Favor reserves in each
        for (uint256 j = 0; j < pairsLen; j++) {
            address pair = lpPairsToExclude[j];
            if (!isLpPairToExclude[pair]) continue; 

            IUniswapV2Pair p = IUniswapV2Pair(pair);

            (uint112 r0, uint112 r1, ) = p.getReserves();
            address t0 = p.token0();
            uint256 favorReserves = (t0 == favor) ? uint256(r0) : uint256(r1);

            uint256 lpTotal = p.totalSupply();
            if (lpTotal == 0 || favorReserves == 0) continue;

            // Get excluded LP token balance of each excluded address and add to excluded balance of Favor
            for (uint256 i = 0; i < excludedLen; i++) {
                uint256 holderLp = p.balanceOf(excludedAddresses[i]);
                if (holderLp == 0) continue;
                favorFromLpHeldByExcluded += (favorReserves * holderLp) / lpTotal;
            }
        }

        return totalSupply - balanceExcluded - favorFromLpHeldByExcluded;
    }


    function pause() external onlyOwner {
        _pause();
        emit ContractPaused(msg.sender);
    }

    function unpause() external onlyOwner {
        _unpause();
        emit ContractUnpaused(msg.sender);
    }

    function setExtraFunds(
        address _daoFund,
        uint256 _daoFundSharedPercent

    ) external onlyOwner {
        require(_daoFund != address(0), "zero");
        require(_daoFundSharedPercent <= 30000, "Dao fund share out of range");
        daoFund = _daoFund;
        daoFundSharedPercent = _daoFundSharedPercent;
        emit DaoFundUpdated(_daoFund, _daoFundSharedPercent);
    }

    function _updateFavorPrice() internal {
        try IOracle(favorOracle).update(){
        } catch {
            revert("Treasury: failed to update FAVOR price");
        }
    }

    function _sendToGrove(uint256 _amount) internal {
        IBasisAsset(favor).mint(address(this), _amount);

        uint256 _daoFundSharedAmount = 0;
        if (daoFundSharedPercent > 0) {
            _daoFundSharedAmount = (_amount * daoFundSharedPercent) / BASIS_DIVISOR;
            IERC20(favor).transfer(daoFund, _daoFundSharedAmount);
            emit DaoFundFunded(block.timestamp, _daoFundSharedAmount);
        }

        _amount -= _daoFundSharedAmount;

        IERC20(favor).forceApprove(grove, _amount);
        IGrove(grove).allocateSeigniorage(_amount);
        emit GroveFunded(block.timestamp, _amount);
    }

    function allocateSeigniorage() external nonReentrant checkCondition checkEpoch whenNotPaused {
        _updateFavorPrice();

        uint256 favorSupply = getFavorCirculatingSupply();

        // Calculate a simple average supply over the epoch window to use for expansion, first epoch uses only the current supply
        uint256 avgSupply = lastEpochCirculatingSupply == 0
        ? favorSupply
        : (favorSupply + lastEpochCirculatingSupply) / 2;

        lastEpochCirculatingSupply = favorSupply;

        uint256 _percentage = getFavorPrice() / 100;
        require(_percentage > 0, "Invalid favor price");

        uint256 min = minSupplyExpansionPercent * 1e13;
        uint256 max = maxSupplyExpansionPercent * 1e13;

        if (_percentage > max) {
            _percentage = max;
        } else if (_percentage < min) {
            _percentage = min;
        }

        uint256 _savedForGrove = (avgSupply * _percentage) / 1e18 / 24; // divide by 24 for each epoch per day

        if (_savedForGrove > 0) {
            _sendToGrove(_savedForGrove);
        }

    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOwner {
        require(address(_token) != address(favor), "Cannot withdraw Favor tokens");
        _token.safeTransfer(_to, _amount);
        emit RecoveredUnsupportedToken(address(_token), _to, _amount);
    }

}