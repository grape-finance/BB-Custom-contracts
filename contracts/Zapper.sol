//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";

import "@aave/core-v3/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";
import "@aave/core-v3/contracts/interfaces/IPool.sol";
import "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";

import "./interfaces/IFavorToken.sol";

contract LPZapper is IFlashLoanSimpleReceiver, Ownable {
    using SafeERC20 for IERC20;

    IPool public POOL;
    IPoolAddressesProvider public ADDRESSES_PROVIDER;

    address public pendingUser;

    IUniswapV2Router02 public router;
    address public PLS;

    address[] public dustTokens;
    mapping(address => bool) public isDustToken;
    mapping(address => address) public favorToToken;
    mapping(address => address) public favorToLp;
    mapping(address => address) public tokenToFavor;

    receive() external payable {}

    constructor(address _owner, address _PLS, address _router) Ownable(_owner) {
        PLS = _PLS;
        router = IUniswapV2Router02(_router);
    }

    /**
     * create liquidity by requesting flash loan, swapping it into pair  and put LP
     * as collateral
     */
    function requestFlashLoan(uint256 _amount, address _favorToken) external {
        address token = favorToToken[_favorToken];
        address lpToken = favorToLp[_favorToken];

        require(token != address(0), "Zapper: unsupported token");
        require(lpToken != address(0), "Zapper: unsupported token");

        pendingUser = msg.sender;

        bytes memory data = abi.encode(msg.sender, _favorToken, lpToken);

        IERC20(_favorToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        (uint112 res0, uint112 res1, ) = IUniswapV2Pair(lpToken).getReserves();
        (uint reserveA, uint reserveB) = _favorToken ==
            IUniswapV2Pair(lpToken).token0()
            ? (res0, res1)
            : (res1, res0);

        uint amountBOptimal = router.quote(_amount, reserveA, reserveB);
        POOL.flashLoanSimple(address(this), token, amountBOptimal, data, 0);
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        require(msg.sender == address(POOL), "not registered pool");
        require(initiator == address(this), "bad initiator");

        (address user, address favorToken, address lpToken) = abi.decode(
            params,
            (address, address, address)
        );
        require(user == pendingUser, "user mismatch");
        pendingUser = address(0);

        uint256 tokenAmount = IERC20(favorToken).balanceOf(address(this));

        IERC20(asset).forceApprove(address(router), amount);
        IERC20(favorToken).forceApprove(address(router), tokenAmount);

        (, , uint256 lpAmount) = router.addLiquidity(
            asset,
            favorToken,
            amount,
            tokenAmount,
            0,
            0,
            address(this),
            block.timestamp + 50
        );

        IERC20(lpToken).forceApprove(address(POOL), lpAmount);

        POOL.supply(lpToken, lpAmount, user, 0);
        POOL.borrow(asset, amount + premium, 2, 0, user);

        IERC20(asset).forceApprove(address(POOL), amount + premium);

        return true;
    }

    //  zap  token into LP with favor
    function zapToken(address _token, uint _amount, uint256 _deadline) public {
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        _zapToken(_token, _amount, _deadline);
    }

    function _zapToken(address _token, uint _amount, uint256 _deadline) public {
        address favor = tokenToFavor[_token];
        require(favor != address(0), "Zap: unsupported");

        address lp = favorToLp[favor];
        require(lp != address(0), "Zap: no lp");

        uint256 half = _amount / 2;

        uint256 balFavor = _swap(_token, favor, half, _deadline);
        IFavorToken(favor).logBuy(msg.sender, balFavor);

        _addLiquidity(_token, favor, half, balFavor, address(this), _deadline);

        uint256 balLP = IERC20(lp).balanceOf(address(this));
        _depositToStronghold(lp, balLP);

        _refundDust(msg.sender);
    }

    function zapPLS(uint256 _deadline) public payable {
        //  wrap
        IWETH(router.WETH()).deposit{value: msg.value}();
        _zapToken(router.WETH(), uint112(msg.value), _deadline);
    }

    //  wrap swapping -  to make it tax exempt
    function _swap(
        address _in,
        address _out,
        uint256 _amount,
        uint256 _deadline
    ) internal returns (uint256) {
        IERC20(_in).approve(address(router), _amount);

        address[] memory path = new address[](2);
        path[0] = _in;
        path[1] = _out;

        uint256 before = IERC20(_out).balanceOf(address(this));
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amount,
            0,
            path,
            address(this),
            _deadline
        );
        uint256 got = IERC20(_out).balanceOf(address(this)) - before;

        require(got > 0, "Zapper: Swap failed");
        return got;
    }

    function _depositToStronghold(address token, uint256 amount) internal {
        IERC20(token).forceApprove(address(POOL), amount);
        POOL.supply(token, amount, msg.sender, 0);
    }

    /**
     * sell favor with taxation.   tax is sent to treasury in  base token
     */
    function sell(address _favor, uint256 _amount) public {
        sellTo(msg.sender, _favor, _amount);
    }

    function sellTo(address _receiver, address _favor, uint256 _amount) public {
        address lp = favorToLp[_favor];
        require(lp != address(0), "Zapper: unsupported token");
    }

    function _addLiquidity(
        address a,
        address b,
        uint256 aAmt,
        uint256 bAmt,
        address to,
        uint256 dl
    ) internal {
        IERC20(a).approve(address(router), aAmt);
        IERC20(b).approve(address(router), bAmt);
        router.addLiquidity(a, b, aAmt, bAmt, 0, 0, to, dl);
    }

    //  wrapper to router call,  to avoid taxation
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external {
        require(favorToToken[tokenA] == tokenB, "Not listed to make LP");
        IERC20(tokenA).transferFrom(msg.sender, address(this), amountADesired);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountBDesired);

        IERC20(tokenA).forceApprove(address(router), amountADesired);
        IERC20(tokenB).forceApprove(address(router), amountBDesired);

        router.addLiquidity(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin,
            to,
            deadline
        );
    }

    //  wrapper for the router call to a coin taxation
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable {
        require(favorToToken[token] == router.WETH(), "Not listed to make LP");
        IERC20(token).transferFrom(
            msg.sender,
            address(this),
            amountTokenDesired
        );
        IERC20(token).forceApprove(address(router), amountTokenDesired);

        router.addLiquidityETH{value: msg.value}(
            token,
            amountTokenDesired,
            amountTokenMin,
            amountETHMin,
            to,
            deadline
        );
    }

    function _refundDust(address recipient) internal {
        uint256 ethBal = address(this).balance;
        if (ethBal > 0) {
            (bool sent, ) = recipient.call{value: ethBal}("");
            require(sent, "refund PLS failed");
        }

        for (uint i = 0; i < dustTokens.length; i++) {
            address t = dustTokens[i];
            uint256 bal = IERC20(t).balanceOf(address(this));
            if (bal > 0) {
                IERC20(t).safeTransfer(recipient, bal);
            }
        }
    }

    function setPool(IPool _pool) external onlyOwner {
        require(address(_pool) != address(0), "Must be a valid address");
        POOL = _pool;
    }

    function setAddressProvider(
        IPoolAddressesProvider _addressProvider
    ) external onlyOwner {
        require(
            address(_addressProvider) != address(0),
            "Must be a valid address"
        );
        ADDRESSES_PROVIDER = _addressProvider;
    }

    function addDustToken(address token) public onlyOwner {
        require(!isDustToken[token], "already added");
        isDustToken[token] = true;
        dustTokens.push(token);
    }

    function removeDustToken(address token) external onlyOwner {
        require(isDustToken[token], "not registered");
        isDustToken[token] = false;
        for (uint i = 0; i < dustTokens.length; i++) {
            if (dustTokens[i] == token) {
                dustTokens[i] = dustTokens[dustTokens.length - 1];
                dustTokens.pop();
                break;
            }
        }
    }

    function adminWithdraw(
        IERC20 _token,
        address _to,
        uint256 _amount
    ) external onlyOwner {
        require(_to != address(0), "Invalid address");
        _token.safeTransfer(_to, _amount);
    }

    function adminWithdrawPLS(address _to, uint256 _amount) external onlyOwner {
        require(_to != address(0), "Invalid address");
        (bool success, ) = _to.call{value: _amount}("");
        require(success, "Transfer failed");
    }

    /**
     * register favor token with LP and base token
     * as this is  a protected method, we expect parameters to be sane
     */
    function addFavor(
        // favor token
        address _favor,
        // lp
        address _lp,
        // base token
        address _token
    ) external onlyOwner {
        require(_favor != address(0), "Invalid address");
        require(_lp != address(0), "Invalid address");
        require(_token != address(0), "Invalid address");
        favorToToken[_favor] = _token;
        favorToLp[_favor] = _lp;
        tokenToFavor[_token] = _favor;
    }

    function removeFavorToken(address _favor) external onlyOwner {
        require(_favor != address(0), "Invalid address");

        delete (tokenToFavor[favorToToken[_favor]]);
        delete (favorToLp[_favor]);
        delete (favorToToken[_favor]);
    }
}
