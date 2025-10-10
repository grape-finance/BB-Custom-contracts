// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;


import "./Favor.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

/**
 * big ass money bin like Scrooges McDuck
 * it provides supply of assets to the liquidator
 *
 * It needs to be registered as minter  and tax exempt to the favors
 */
contract MoneyBin is Ownable2Step {

    //  default values for pulsex,  can be adjusted
    uint256 public  VAL997 = 9971;
    uint256 public  constant VAL1000 = 10000;


    IUniswapV2Router02 public  router;
    IUniswapV2Factory public factory;

    // executor is a low value technical address, which will be  used by external triggerr to perform duties
    mapping(address => bool) public isExecutor;
    // destination to be supplied
    address public receiver;

    // mapping from asset to favor
    mapping(IERC20 => Favor) public asset2Favor;

    event Withdrawn(address token, uint256 amount, address receiver);

    //  max basis points of reserves to mint in one
    uint256 public mintThreshold = 50;
    uint256 immutable DENOMINATOR = 10000;

    constructor(address _owner, IUniswapV2Router02 _router, IUniswapV2Factory _factory)  Ownable(_owner) {
        router = _router;
        factory = _factory;
    }

    // mint suitable amount of asset0 directly to the receiver
    function mintAsset(IERC20 _asset, uint256 _amount) public {
        require(_amount > 0, 'MoneyBin: insufficient amount');
        Favor favor = asset2Favor[_asset];
        require(address(favor) != address(0), "MoneyBin: favor not registered");

        //  so,   we have favor.  not calculate  how much we have to put into pair,
        // to get desired amount of tokens
        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(address(favor), address(_asset)));
        // reserves
        uint256 rF;
        uint256 rA;
        // out amounts
        uint256 a0Out;
        uint256 a1Out;

        if (pair.token0() == address(favor)) {
            (rF, rA,) = pair.getReserves();
            a1Out = _amount;
        } else {
            (rA, rF,) = pair.getReserves();
            a0Out = _amount;
        }

        // check reserves
        require(_amount < rA * mintThreshold / DENOMINATOR, "MoneyBin: over slippage limit");

        //  calculate desired amount of favor tokens to put into pair
        //  as those values are coming from pair, and are contrained to U112
        //  we are on safe side here
        uint256 numerator = rF * _amount * VAL1000;
        uint256 denominator = (rA - _amount) * VAL997;
        uint256 amountIn = numerator / denominator + 1;

        // can not mint directly to the pair, as it is not tax exempt
        favor.mint(address(this), amountIn);
        favor.transfer(address(pair), amountIn);

        // ... and swap
        pair.swap(a0Out, a1Out, address(this), new bytes(0));

    }

    function registerFavor(IERC20 _asset, Favor _favor) public onlyOwner {
        asset2Favor[_asset] = _favor;
    }

    // supply configured receiver with desired amount of the asset
    // we assume caller know what he does
    function supply(IERC20 _asset, uint256 _amount) public onlyExecutor {
        IERC20(_asset).transfer(receiver, _amount);
    }

    function setThreshold(uint256 _th) public onlyOwner {
        require(_th > 0, "MoneyBin: muste be above 0");
        require(_th < DENOMINATOR, "MoneyBin: muste be below 10000");

        mintThreshold = _th;
    }

    function setRouter(IUniswapV2Router02 _router) public onlyOwner {
        router = _router;
    }

    function setVal997(uint256 _v) public onlyOwner {
        VAL997 = _v;
    }

    function setFactory(IUniswapV2Factory _factory) public onlyOwner {
        factory = _factory;
    }

    function setExecutor(address _executor, bool status) public onlyOwner {
        isExecutor[_executor] = status;
    }

    function setReceiver(address _receiver) public onlyOwner {
        receiver = _receiver;
    }

    /**
    * @dev Throws if called by any account other than the owner.
     */
    modifier onlyExecutor() {
        require(isExecutor[_msgSender()], "MoneyBin: not executor");
        _;
    }

// withdraw  assets
    function withdraw(address _token, uint256 _amount, address _receiver) public onlyOwner {
        IERC20(_token).transfer(_receiver, _amount);
        emit Withdrawn(_token, _amount, _receiver);
    }

}
