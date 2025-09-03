// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./interfaces/PriceProvider.sol";
import "./interfaces/BBToken.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {IFavorToken} from "./interfaces/IFavorToken.sol";

/**
 * base favor contract  with common logic
 */
contract AbstractFavor is IFavorToken, ERC20Burnable, Ownable {

    uint256 public constant MULTIPLIER = 10000;
    uint256 public constant MAX_TAX = 5000; // 50% MAX Sell Tax

    uint256 public sellTax = 5000;
    uint256 public bonusRate = 4400; // Buy bonus to buyer in esteem
    uint256 public treasuryBonusRate = 2500; // 25% extra bonus minted to protocol treasury multisig on top of users minted amount
    address public treasury; // Treasury multisig wallet

    BBToken public esteem;
    PriceProvider public priceProvider; // Esteem mint & redeem contract

    mapping(address => bool) public isTaxExempt;
    mapping(address => bool) public isMinter; // Approved minters of Favor token
    mapping(address => bool) public isBuyWrapper; // Buy uniswap wrapper address to log bonus esteem on buys
    mapping(address => uint256) public pendingBonus; // User pending esteem bonus for buys

    event MinterAdded(address indexed account);
    event MinterRemoved(address indexed account);
    event TreasuryUpdated(address indexed newTreasury);
    event PriceProviderUpdated(address indexed newProvider);
    event EsteemTokenUpdated(address indexed newEsteem);
    event SellTaxUpdated(uint256 newTax);
    event BonusRatesUpdated(uint256 newBonusRate, uint256 newtreasuryBonusRate);
    event EsteemBonusLogged(address indexed recipient, uint256 amount, uint256 treasuryAmount);
    event UserBonusClaimed(address indexed recipient, uint256 amount);
    event TaxExemptStatusUpdated(address indexed account, bool isExempt);
    event BuyWrapperUpdated(address indexed wrapper, bool isActive);



    constructor(address _owner, string memory _name, string memory _symbol, uint256 _initialSupply, address _treasury, address _esteem)
    ERC20(_name, _symbol)
    Ownable(_owner)
    {
        require(_esteem != address(0), "Invalid Esteem address");
        require(_treasury != address(0), "Invalid Treasury address");

        treasury = _treasury;
        esteem = BBToken(_esteem);

        _mint(_owner, _initialSupply);
    }


    function mint(address _recipient, uint256 _amount) public {
        require(isMinter[msg.sender], "Not authorized to mint");
        _mint(_recipient, _amount);
    }

    function _isTaxExempt(address _recipient) internal view returns (bool) {
        return isTaxExempt[_recipient];
    }

    function calculateFavorBonuses(uint256 _amount) public view returns (uint256 userBonus_, uint256 treasuryBonus_) {
        uint256 favorPrice = priceProvider.getLatestTokenPrice(address(this)); // Favor price in USD as 18 Decimals

        // Compute USD value of the amount (also 18 decimals)
        uint256 usdBuyAmount = (_amount * favorPrice) / 1e18;

        // Calculate bonus amount in USD value
        uint256 bonusAmount = (usdBuyAmount * bonusRate) / MULTIPLIER;

        // Get esteem token price in USD (18 decimals)
        uint256 rate = priceProvider.esteemRate();
        require(rate > 0, "Invalid Esteem rate");

        // Convert USD bonus amount to esteem tokens
        userBonus_ = (bonusAmount * 1e18) / rate;

        // Treasury bonus as a % of user bonus
        treasuryBonus_ = (userBonus_ * treasuryBonusRate) / MULTIPLIER;

    }

    /**
     * @dev See {IERC20-_update}.
     * here we apply taxation.  if destination is a contract, we treat is as a sell.
     * edge cases like buy via approved contracts  while minting  ersteem of whatever
     * will be tax exempt.
     */
    function _update(address _from, address _to, uint256 _value) internal override {
        bool destinationIsContract = _to.code.length != 0;


        if (_isTaxExempt(_to) || _isTaxExempt(_from)) {
            super._update(_from, _to, _value);
            return;
        }

        uint256 taxAmount = 0;

        if (destinationIsContract) {
            taxAmount = (_value * sellTax) / MULTIPLIER;
        }

        // tax goes to treasury
        if (taxAmount > 0) {
            super._update(_from, treasury, taxAmount);
            _value -= taxAmount;
        }

        super._update(_from, _to, _value);
    }


    function logBuy(address _user, uint256 _amount) external {
        // Buy wrapper contract logs user buys of Favor to track esteem bonus accurately
        require(isBuyWrapper[msg.sender], "Not authorised to log buy");

        (uint256 userBonus, uint256 treasuryBonus) = calculateFavorBonuses(_amount);
        pendingBonus[_user] += userBonus;

        esteem.mint(treasury, treasuryBonus); // Esteem bonus to treasury minted
        emit EsteemBonusLogged(_user, userBonus, treasuryBonus);
    }

    function claimBonus() external {
        // Claim accumulated esteem buy bonus for user
        uint256 bonus = pendingBonus[msg.sender];
        require(bonus > 0, "No bonus available");
        pendingBonus[msg.sender] = 0;
        esteem.mint(msg.sender, bonus);
        emit UserBonusClaimed(msg.sender, bonus);
    }

    function addMinter(address _account) external onlyOwner {
        isMinter[_account] = true;
        emit MinterAdded(_account);
    }

    function removeMinter(address _account) external onlyOwner {
        isMinter[_account] = false;
        emit MinterRemoved(_account);
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid Treasury address");
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    function setPriceProvider(address _priceProvider) external onlyOwner {
        require(_priceProvider != address(0), "Invalid Esteem Minter address");
        priceProvider = PriceProvider(_priceProvider);
        emit PriceProviderUpdated(_priceProvider);
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

    function setBonusRates(uint256 _bonusRate, uint256 _treasuryBonusRate) external onlyOwner {
        require(_bonusRate <= MULTIPLIER, "User bonus cannot be larger than max multiplier");
        require(_treasuryBonusRate <= MULTIPLIER, "Tresury bonus cannot be larger than max multiplier");
        bonusRate = _bonusRate;
        treasuryBonusRate = _treasuryBonusRate;
        emit BonusRatesUpdated(_bonusRate, _treasuryBonusRate);
    }

    function setTaxExempt(address account, bool exempt) external onlyOwner {
        isTaxExempt[account] = exempt;
        emit TaxExemptStatusUpdated(account, exempt);
    }


    function setBuyWrapper(address _wrapper, bool value) external onlyOwner {
        require(_wrapper != address(0), "Invalid wrapper address");
        isBuyWrapper[_wrapper] = value;
        emit BuyWrapperUpdated(_wrapper, value);
    }
}