// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@aave/core-v3/contracts/interfaces/IPool.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";

import "./interfaces/BBToken.sol";
import "./interfaces/IMasterOracle.sol";


contract MintRedeemer is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    uint256 public constant PERIOD = 1 days;
    uint256 public constant MULTIPLIER = 10000;

    BBToken public esteem; 
    IPool public POOL;

    address public immutable WPLS = 0xA1077a294dDE1B09bB078844df40758a5D0f9a27; 
    address public team = 0x1EA35487AE62322F61f4C0F639a598d9eEB2F340;
    address public holding = 0x6831f815963FfCe95521271b94164eb4C82e7621;

    uint256 public startTime;
    uint256 public epoch = 1;
    uint256 public esteemRate = 21 * 1e18;       // $21 per Esteem start price
    uint256 public redeemRate = 7000;      // 70% in favor for Esteem redeemptions
    uint256 public treasuryBonusRate = 2500; // 25% extra bonus minted to protocol treasury multisig on top of users minted amount 
    uint256 public dailyRateIncrease = 0.25 ether;

    mapping(address => bool) public allowedMintTokens; // Tokens that can be used to mint Esteem
    mapping(address => bool) public favorTokens;
    mapping(address => bool) public isApprovedUser;
    mapping(address => address) public priceOracles;

    event Minted(address indexed user, uint256 inputAmount, uint256 esteemAmount);
    event Redeemed(address indexed user, uint256 esteemAmount, uint256 rewardAmount);
    event RateUpdated(uint256 newRate);
    event NewDailyRateIncrease(uint256 newRate);
    event RedeemRateUpdated(uint256 newRate);
    event TreasuryBonusUpdated(uint256 newBonus);
    event TreasuryUpdated(address indexed newHolding, address indexed newTeam);
    event AdminWithdraw(address indexed token, address indexed to, uint256 amount);
    event NewPOOL(address indexed poolAddress);
    event ContractPaused(address indexed admin);
    event ContractUnpaused(address indexed admin);
    event OracleUpdated(address indexed token, address indexed oracle);
    event ApprovedUserSet(address indexed user, bool allowed);
    event AllowedMintTokenSet(address indexed token, bool allowed);
    event ActiveFavorTokenSet(address indexed token, bool allowed);

    constructor(address _esteem, uint256 _startTime, address _owner) Ownable(_owner){
        require(_esteem != address(0), "Invalid Esteem address");
        require(_startTime >= block.timestamp, "Cannot start in past");

        startTime = _startTime;
        esteem = BBToken(_esteem);
    }

    function mintEsteemWithPLS(uint256 deadline) external payable nonReentrant whenNotPaused {
        require(block.timestamp <= deadline, "Mint: deadline passed");
        require(msg.value > 0, "Amount must be > 0");

        uint256 outputAmount = _calculateEsteemMint(msg.value, address(0));
        require(outputAmount > 0, "Increase your amount");

        uint256 treasuryAmount = (outputAmount * treasuryBonusRate) / MULTIPLIER;

        _depositToStronghold(address(0), msg.value);

        esteem.mint(msg.sender, outputAmount);
        esteem.mint(team, treasuryAmount);

        emit Minted(msg.sender, msg.value, outputAmount);
    }

    function mintEsteemWithToken(uint256 amount, address token, uint256 deadline) external nonReentrant whenNotPaused {
        require(block.timestamp <= deadline, "Mint: deadline passed");
        require(allowedMintTokens[token], "Token not accepted");
        require(amount > 0, "Amount must be > 0");

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        uint256 outputAmount = _calculateEsteemMint(amount, token);
        require(outputAmount > 0, "Increase your amount");

        uint256 treasuryAmount = (outputAmount * treasuryBonusRate) / MULTIPLIER;

        _depositToStronghold(token, amount);

        esteem.mint(msg.sender, outputAmount);
        esteem.mint(team, treasuryAmount);

        emit Minted(msg.sender, amount, outputAmount);
    }

    function redeemFavor(uint256 _esteemAmount, BBToken _favorToken) external nonReentrant whenNotPaused {
        require(favorTokens[address(_favorToken)], "Unsupported favor token");
        require(_esteemAmount > 0, "Amount must be > 0");

        uint256 userAmount = _calculateRedeemAmounts(_esteemAmount, address(_favorToken));

        esteem.burnFrom(msg.sender, _esteemAmount);

        _favorToken.mint(msg.sender, userAmount);

        emit Redeemed(msg.sender, _esteemAmount, userAmount);
    }

    // Standardize all tokens to 18 decimals
    function _normalizeTokenAmount(uint256 amount, address token) internal view returns (uint256) {

        uint8 tokenDecimals = token == address(0)
                ? 18
                : IERC20Metadata(token).decimals();

        if (tokenDecimals == 18) {
            return amount;
        } else {
            // e.g. USDT: 6 → bump 10**(18-6)
            return amount * (10 ** (18 - tokenDecimals));
        } 
     }

    /// @notice Deposit 80% of treasury amount into the lending pool immediately and send remaining as base tokens to team pay multisig
     function _depositToStronghold(address token, uint256 amount) internal {
        uint256 treasuryAmt = (amount * 20) / 100;
        uint256 toDeposit = amount - treasuryAmt;
        if (token == address(0)) {
            IWETH(WPLS).deposit{value: amount }();
            IERC20(WPLS).forceApprove(address(POOL), toDeposit);
            POOL.supply(WPLS, toDeposit, holding, 0);
            IERC20(WPLS).safeTransfer(team, treasuryAmt);
        } else {
            IERC20(token).forceApprove(address(POOL), toDeposit);
            POOL.supply(token, toDeposit, holding, 0);
            IERC20(token).safeTransfer(team, treasuryAmt);
        }
    }

    // Calculates user output for minting Esteem based on the token input
    function _calculateEsteemMint(uint256 amount, address token) internal view returns (uint256) {
        uint256 price = getLatestTokenPrice(token); 
        uint256 normalized = _normalizeTokenAmount(amount, token);
        return (normalized * price) / esteemRate;
    }

    // Calculates user output for a given ESTEEM redemption into a Favor token
    function _calculateRedeemAmounts(uint256 esteemAmount, address favorToken) internal view returns (uint256 userReceives) {
        uint256 favorPrice = getLatestTokenPrice(favorToken);
        require(favorPrice > 0, "Invalid favor price");

        uint256 esteemToFavor = (esteemAmount * esteemRate) / favorPrice;
        userReceives = (esteemToFavor * redeemRate) / MULTIPLIER;
    }

    // Public view redeem function for UI
    function previewFavorRedeem(uint256 esteemAmount, address favorToken) public view returns (uint256 userReceives) {
        return _calculateRedeemAmounts(esteemAmount, favorToken);
    }

    // Public view mint calculation for UI
    function previewMint(uint256 amount, address token) public view returns (uint256 userReceives) {
        return _calculateEsteemMint(amount, token);
    }

    function getLatestTokenPrice(address token) public view returns (uint256) {
        // All oracles output token price in USD value as 18 decimals
        address oracle = priceOracles[token];
        require(oracle != address(0), "No oracle set for token");
        uint256 price = IMasterOracle(oracle).getLatestPrice(token);
        require(price > 0, "Invalid price from Oracle");
        return price;
    }

    function getLatestTokenTWAP(address token) public view returns (uint256) {
        // All oracles output token price as TWAP value in paired token
        address oracle = priceOracles[token];
        require(oracle != address(0), "No oracle set for token");
        uint256 price = IMasterOracle(oracle).getTokenTWAP(token);
        require(price > 0, "Invalid price from Oracle");
        return price;
    }

    function nextEpochTime() public view returns (uint256) {
        return startTime + epoch * PERIOD;
    }

    function updateEsteemRate() external {
        require(isApprovedUser[msg.sender], "Not approved user");
        require(block.timestamp >= startTime, "not started");
        require(block.timestamp >= nextEpochTime(), "Updater epoch not passed");
        epoch += 1;
        esteemRate += dailyRateIncrease;
        emit RateUpdated(esteemRate);
    }

    function setApprovedUser(address user, bool allowed) external onlyOwner {
        require(user != address(0), "Zero address not allowed");
        isApprovedUser[user] = allowed;
        emit ApprovedUserSet(user, allowed);
    }

    function setDailyRateIncrease(uint256 _newRate) external onlyOwner {
        dailyRateIncrease = _newRate;
        emit NewDailyRateIncrease(_newRate);
    }

    function setEsteemRate(uint256 _rate) external onlyOwner {
        require(_rate > 0, "Esteem Rate must be > 0");
        esteemRate = _rate;
        emit RateUpdated(_rate);
    }

    function setPool(address _pool) external onlyOwner {
        require(_pool != address(0), "Must be a valid address");
        POOL = IPool(_pool);
        emit NewPOOL(_pool);
    }

    function setRedeemRate(uint256 _redeemRate) external onlyOwner {
        require(_redeemRate <= MULTIPLIER, "Cannot exceed 100%");
        redeemRate = _redeemRate;
        emit RedeemRateUpdated(_redeemRate);
    }

    function setTreasuryBonus(uint256 _treasuryBonusRate) external onlyOwner {
        require(_treasuryBonusRate <= MULTIPLIER, "Cannot exceed 100%");
        treasuryBonusRate = _treasuryBonusRate;
        emit TreasuryBonusUpdated(_treasuryBonusRate);
    }

    function setTreasury(address _holding, address _team) external onlyOwner {
        require(_holding != address(0), "Invalid Holding address");
        require(_team != address(0), "Invalid Team address");
        holding = _holding;
        team = _team;
        emit TreasuryUpdated(_holding, _team);
    }

    function setPriceOracle(address token, address oracle) external onlyOwner {
        require(oracle != address(0), "Invalid oracle");
        priceOracles[token] = oracle;
        emit OracleUpdated(token, oracle);
    }

    function setAllowedMintToken(address token, bool allowed) external onlyOwner {
        require(token != address(0), "Invalid token");
        allowedMintTokens[token] = allowed;
        emit AllowedMintTokenSet(token, allowed);
    }

    function setActiveFavorToken(address token, bool allowed) external onlyOwner {
        require(token != address(0), "Invalid token");
        favorTokens[token] = allowed;
        emit ActiveFavorTokenSet(token, allowed);
    }

    // Admin withdraw incase of stuck or mistakenly sent tokens, no user tokens are stored in this contract
    function adminWithdraw(IERC20 _token, address _to, uint256 _amount) external onlyOwner {
        require(_to != address(0), "Invalid address");
        _token.safeTransfer(_to, _amount);
        emit AdminWithdraw(address(_token), _to, _amount);
    }

    function adminWithdrawPLS(address _to, uint256 _amount) external onlyOwner {
        require(_to != address(0), "Invalid address");
        (bool success, ) = _to.call{value: _amount}("");
        require(success, "Transfer failed");
        emit AdminWithdraw(address(0), _to, _amount);
    }

    function pause() external onlyOwner {
        _pause();
        emit ContractPaused(msg.sender);
    }

    function unpause() external onlyOwner {
        _unpause();
        emit ContractUnpaused(msg.sender);
    }

    receive() external payable {}

}