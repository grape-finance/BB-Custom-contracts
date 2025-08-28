//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniswapV2Pair.sol";

import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces//IFlashLoanSimpleReceiver.sol";
import "./interfaces/IWPLS.sol";
import "./interfaces/IFavorToken.sol";

contract LPZapper is IFlashLoanSimpleReceiver, Ownable {
    using SafeERC20 for IERC20;
    IPool public override POOL;

    error UNSUPORTED_TOKEN();

    IUniswapV2Router02 public immutable router;

    address public immutable PLS;

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

    function getOptimalAddLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired
    ) public view returns (uint amountA, uint amountB) {
        address pair = IUniswapV2Factory(router.factory()).getPair(
            tokenA,
            tokenB
        );
        require(pair != address(0), "Pair does not exist");

        (uint112 res0, uint112 res1, ) = IUniswapV2Pair(pair).getReserves();
        (uint reserveA, uint reserveB) = tokenA == IUniswapV2Pair(pair).token0()
            ? (res0, res1)
            : (res1, res0);

        uint amountBOptimal = router.quote(amountADesired, reserveA, reserveB);

        return (amountADesired, amountBOptimal);
    }

    function requestFlashLoan(uint256 amount, address favorToken) external {
        require(favorToToken[favorToken] != address(0), UNSUPORTED_TOKEN());
        require(favorToLp[favorToken] != address(0), UNSUPORTED_TOKEN());
        address token = favorToToken[favorToken];
        address lpToken = favorToLp[favorToken];

        bytes memory data = abi.encode(msg.sender, favorToken, lpToken);

        IERC20(favorToken).safeTransferFrom(msg.sender, address(this), amount);
        (, uint256 amtB) = getOptimalAddLiquidity(favorToken, token, amount);

        POOL.flashLoanSimple(address(this), token, amtB, data, 0);
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        (address user, address favorToken, address lpToken) = abi.decode(
            params,
            (address, address, address)
        );

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

    function zap(
        address token,
        uint256 amount,
        uint256 deadline
    ) external payable {
        require(block.timestamp <= deadline, "Zap: deadline out of time");

        if (token == PLS) {
            require(msg.value == amount, "Zap: value mismatch");
            _zapPLS(tokenToFavor[token], amount, deadline);
        } else if (tokenToFavor[token] != address(0)) {
            _zapToken(tokenToFavor[token], amount, deadline);
        } else {
            revert("Zap: unsupported");
        }

        _refundDust(msg.sender);
    }

    function _zapPLS(address _favor, uint256 amount, uint256 dl) internal {
        uint256 half = amount / 2;

        IWPLS(router.WPLS()).deposit{value: half}();

        address token = router.WPLS();
        address lp = favorToLp[_favor];

        uint256 balFavor = _swapAndLog(token, _favor, half, dl);

        _addLiquidityETH(_favor, half, balFavor, address(this), dl);
        uint256 balLP = IERC20(lp).balanceOf(address(this));
        _depositToStronghold(lp, balLP);
    }

    function _zapToken(address _favor, uint256 amount, uint256 dl) internal {
        uint256 half = amount / 2;
        address token = favorToToken[_favor];
        address lp = favorToLp[_favor];

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        uint256 balFavor = _swapAndLog(token, _favor, half, dl);
        _addLiquidity(token, _favor, half, balFavor, address(this), dl);

        uint256 balLP = IERC20(lp).balanceOf(address(this));
        _depositToStronghold(lp, balLP);
    }

    function _swapAndLog(
        address inToken,
        address favorToken,
        uint256 amt,
        uint256 dl
    ) internal returns (uint256) {
        IERC20(inToken).approve(address(router), amt);

        address[] memory path = new address[](2);
        path[0] = inToken;
        path[1] = favorToken;

        uint256 before = IERC20(favorToken).balanceOf(address(this));
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amt,
            0,
            path,
            address(this),
            dl
        );
        uint256 got = IERC20(favorToken).balanceOf(address(this)) - before;

        require(got > 0, "Swap failed");
        IFavorToken(favorToken).logBuy(msg.sender, got);
        return got;
    }

    function _depositToStronghold(address token, uint256 amount) internal {
        IERC20(token).forceApprove(address(POOL), amount);
        POOL.supply(token, amount, msg.sender, 0);
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

    function _addLiquidityETH(
        address token,
        uint256 ethAmt,
        uint256 tokenAmt,
        address to,
        uint256 dl
    ) internal {
        IERC20(token).approve(address(router), tokenAmt);
        router.addLiquidityETH{value: ethAmt}(token, tokenAmt, 0, 0, to, dl);
    }

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

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable {
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

    function setPool(address _pool) external onlyOwner {
        require(_pool != address(0), "Must be a valid address");
        POOL = IPool(_pool);
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

    function addFavorToToken(
        address _favor,
        address _token
    ) external onlyOwner {
        require(_favor != address(0), "Invalid address");
        require(_token != address(0), "Invalid address");
        favorToToken[_favor] = _token;
    }

    function addFavorToLp(address _favor, address _lp) external onlyOwner {
        require(_favor != address(0), "Invalid address");
        require(_lp != address(0), "Invalid address");
        favorToLp[_favor] = _lp;
    }

    function addTokenToFavor(
        address _token,
        address _favor
    ) external onlyOwner {
        require(_favor != address(0), "Invalid address");
        require(_token != address(0), "Invalid address");
        tokenToFavor[_token] = _favor;
    }

    function removeFavorToken(
        address _favor
    ) external onlyOwner {
        require(_favor != address(0), "Invalid address");     
        tokenToFavor[tokenToFavor[_favor]] = address(0);
        favorToLp[_favor] = address(0);
        favorToToken[_favor] = address(0);
    }
}
