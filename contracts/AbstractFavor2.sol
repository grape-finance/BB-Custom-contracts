// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./interfaces/Minter.sol";
import "./interfaces/BBToken.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/UniV2Lib.sol";

/**
 * base favor contract  with common logic
 */
contract AbstractFavor is ERC20Burnable, Ownable {
    uint256 public constant MULTIPLIER = 10000;
    uint256 public constant MAX_TAX = 5000; // 50% MAX Sell Tax

    uint256 public sellTax = 5000;
    uint256 public bonusRate = 4400; // Buy bonus to buyer in esteem
    uint256 public treasuryBonusRate = 2500; // 25% extra bonus minted to protocol treasury multisig on top of users minted amount
    address public treasury; // Treasury multisig wallet
    address public basePair;
    bool private isTax = true;
    address public liquidityManager;

    BBToken public esteem;
    Minter public esteemMinter; // Esteem mint & redeem contract

    mapping(address => bool) public isMarketPair; // LP pair address
    mapping(address => bool) public isTaxExempt;
    mapping(address => bool) public isMinter; // Approved minters of Favor token
    mapping(address => bool) public isBuyWrapper; // Buy uniswap wrapper address to log bonus esteem on buys
    mapping(address => uint256) public pendingBonus; // User pending esteem bonus for buys
    mapping(address => bool) public whitelisted; // whether this address is whitelisted contract

    event MinterAdded(address indexed account);
    event MinterRemoved(address indexed account);
    event TreasuryUpdated(address indexed newTreasury);
    event EsteemMinterUpdated(address indexed newMinter);
    event EsteemTokenUpdated(address indexed newEsteem);
    event SellTaxUpdated(uint256 newTax);
    event BonusRatesUpdated(uint256 newBonusRate, uint256 newtreasuryBonusRate);
    event EsteemBonusLogged(
        address indexed recipient,
        uint256 amount,
        uint256 treasuryAmount
    );
    event UserBonusClaimed(address indexed recipient, uint256 amount);
    event TaxExemptStatusUpdated(address indexed account, bool isExempt);
    event MarketPairUpdated(address indexed pair, bool isPair);
    event BuyWrapperUpdated(address indexed wrapper, bool isActive);
    event WhitelistStatusUpdated(address indexed wrapper, bool isActive);
    event TreassurySwap(address indexed treasury, uint amount);

    constructor(
        address _owner,
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply,
        address _treasury,
        address _esteem
    ) ERC20(_name, _symbol) Ownable(_owner) {
        require(_esteem != address(0), "Invalid Esteem address");
        require(_treasury != address(0), "Invalid Treasury address");

        treasury = _treasury;
        esteem = BBToken(_esteem);

        _mint(_owner, _initialSupply);
    }

    function mint(address recipient_, uint256 amount_) public {
        require(isMinter[msg.sender], "Not authorized to mint");
        _mint(recipient_, amount_);
    }

    function _isTaxExempt(
        address sender,
        address recipient
    ) internal view returns (bool) {
        return isTaxExempt[sender] || isTaxExempt[recipient];
    }

    function calculateFavorBonuses(
        uint256 amount
    ) public view returns (uint256 userBonus, uint256 treasuryBonus) {
        uint256 favorPrice = esteemMinter.getLatestTokenPrice(address(this)); // Favor price in USD as 18 Decimals

        // Compute USD value of the amount (also 18 decimals)
        uint256 usdBuyAmount = (amount * favorPrice) / 1e18;

        // Calculate bonus amount in USD value
        uint256 bonusAmount = (usdBuyAmount * bonusRate) / MULTIPLIER;

        // Get esteem token price in USD (18 decimals)
        uint256 rate = esteemMinter.esteemRate();
        require(rate > 0, "Invalid Esteem rate");

        // Convert USD bonus amount to esteem tokens
        userBonus = (bonusAmount * 1e18) / rate;

        // Treasury bonus as a % of user bonus
        treasuryBonus = (userBonus * treasuryBonusRate) / MULTIPLIER;

        return (userBonus, treasuryBonus);
    }

    //Checks is to address is an lp token

    function isPair(address to) public view returns (bool) {
        // default assume not a pair
        bool success;

        try IUniswapV2Pair(to).token0() returns (address t0) {
            // if token0() doesn't revert, very likely a valid pair
            // we could also sanity-check token1() != address(0)
            success = (t0 != address(0));
        } catch {
            success = false;
        }

        return success;
    }

    // allows lp manager to turn on tax after lp adding
    function turnOnTax() external {
        require(msg.sender == liquidityManager, "Not Liqudity Manager");
        isTax = true;
    }

    // allows lp manager to turn off the tax to add lp
    function turnOffTax() external {
        require(msg.sender == liquidityManager, "Not Liqudity Manager");
        isTax = false;
    }
    // changes the allowed liquidity manager
    function changeLiquidityManager(address _lpManager) external onlyOwner{
        liquidityManager = _lpManager;
    }

// sets the base pair for swapping to treasury
    function setBasePair(address _basePair) external onlyOwner{
        basePair = _basePair;
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - the caller must have a balance of at least `value`.
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        // checks if lp token or not

        bool isPairCheck = isPair(to);

        if (_isTaxExempt(from, to)) {
            super._update(from, to, value);
            return;
        }

        uint256 taxAmount = 0;

        bool isBuy = isMarketPair[from]; // Label LP interactions For readability
    // checks if the to is pair and if it is taxed
        if (isPairCheck && isTax) {
            taxAmount = (value * sellTax) / MULTIPLIER;
        }
    // if it is a buy then log and mint the eoa that started the transaction. 
    // by using the tx.origin, it also prevents a contract to loop this to then use the esteem to smelt within the same transaction
        if (isBuy) {
            logBuy(tx.origin, value);
        }

        if (taxAmount > 0) {
            // transfer to lp for swap
            super._update(from, basePair, taxAmount);
            // lp swap logic
            (uint112 r0, uint112 r1, ) = IUniswapV2Pair(basePair).getReserves();
            address t0 = IUniswapV2Pair(basePair).token0();
            (uint reserveIn, uint reserveOut, bool zeroForOne) = address(
                this
            ) == t0
                ? (uint(r0), uint(r1), true)
                : (uint(r1), uint(r0), false);

            uint amountOut = PulseXLibrary.getAmountOut(
                taxAmount,
                reserveIn,
                reserveOut
            );

            // amount0Out/amount1Out depends on direction
            (uint amount0Out, uint amount1Out) = zeroForOne
                ? (uint(0), amountOut)
                : (amountOut, uint(0));

            // Call swap — pair will send tokenOut to `treasury`
            IUniswapV2Pair(basePair).swap(
                amount0Out,
                amount1Out,
                treasury,
                new bytes(0)
            );
            value -= taxAmount;
            emit TreassurySwap(treasury, amountOut);
        }

        super._update(from, to, value);
    }

    function logBuy(address user, uint256 amount) internal {
        // Buy wrapper contract logs user buys of Favor to track esteem bonus accurately

        (uint256 userBonus, uint256 treasuryBonus) = calculateFavorBonuses(
            amount
        );
        pendingBonus[user] += userBonus;

        esteem.mint(treasury, treasuryBonus); // Esteem bonus to treasury minted
        emit EsteemBonusLogged(user, userBonus, treasuryBonus);
    }

    function claimBonus() external {
        // Claim accumulated esteem buy bonus for user
        uint256 bonus = pendingBonus[msg.sender];
        require(bonus > 0, "No bonus available");
        pendingBonus[msg.sender] = 0;
        esteem.mint(msg.sender, bonus);
        emit UserBonusClaimed(msg.sender, bonus);
    }

    // set whitelisting status for contract address
    function setWhitelist(address adr, bool isWhitelisted) external onlyOwner {
        whitelisted[adr] = isWhitelisted;
        emit WhitelistStatusUpdated(adr, isWhitelisted);
    }

    function addMinter(address account) external onlyOwner {
        isMinter[account] = true;
        emit MinterAdded(account);
    }

    function removeMinter(address account) external onlyOwner {
        isMinter[account] = false;
        emit MinterRemoved(account);
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid Treasury address");
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    function setEsteemMinter(address _esteemMinter) external onlyOwner {
        require(_esteemMinter != address(0), "Invalid Esteem Minter address");
        esteemMinter = Minter(_esteemMinter);
        emit EsteemMinterUpdated(_esteemMinter);
    }

    function setEsteem(address _esteem) external onlyOwner {
        require(_esteem != address(0), "Invalid Esteem address");
        esteem = BBToken(_esteem);
        emit EsteemTokenUpdated(_esteem);
    }

    function setSellTax(uint256 _sellTax) external onlyOwner {
        require(_sellTax <= MAX_TAX, "Sell tax too high");
        sellTax = _sellTax;
        emit SellTaxUpdated(_sellTax);
    }

    function setBonusRates(
        uint256 _bonusRate,
        uint256 _treasuryBonusRate
    ) external onlyOwner {
        require(
            _bonusRate <= MULTIPLIER,
            "User bonus cannot be larger than max multiplier"
        );
        require(
            _treasuryBonusRate <= MULTIPLIER,
            "Tresury bonus cannot be larger than max multiplier"
        );
        bonusRate = _bonusRate;
        treasuryBonusRate = _treasuryBonusRate;
        emit BonusRatesUpdated(_bonusRate, _treasuryBonusRate);
    }

    function setTaxExempt(address account, bool exempt) external onlyOwner {
        isTaxExempt[account] = exempt;
        emit TaxExemptStatusUpdated(account, exempt);
    }

    function setMarketPair(address pair, bool value) external onlyOwner {
        isMarketPair[pair] = value;
        emit MarketPairUpdated(pair, value);
    }

    function setBuyWrapper(address _wrapper, bool value) external onlyOwner {
        require(_wrapper != address(0), "Invalid wrapper address");
        isBuyWrapper[_wrapper] = value;
        emit BuyWrapperUpdated(_wrapper, value);
    }
}
