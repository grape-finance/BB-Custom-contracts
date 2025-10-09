// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;


import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

/**
 * big ass money bin like Scrooges McDuck
 * it provides supply of
 */
contract MoneyBin is Ownable2Step {

    IUniswapV2Router02 public  router;
    IUniswapV2Factory public factory;

    // executor is a low value technical address, which will be  used by external triggerr to perform duties
    mapping(address => bool) public isExecutor;

    // destination to be supplied
    address public receiver;

    constructor(address _owner, IUniswapV2Router02 _router, IUniswapV2Factory _factory)  Ownable(_owner) {
        router = _router;
        factory = _factory;
    }

    function setRouter(IUniswapV2Router02 _router) public onlyOwner {
        router = _router;
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
        require(isExecutor[_msgSender()], "MenoeyBin: not executor");
        _;
    }


}
