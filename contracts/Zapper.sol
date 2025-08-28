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

    IUniswapV2Router02 public constant router = IUniswapV2Router02(0x165C3410fC91EF562C50559f7d2289fEbed552d9);
    address public constant PDAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant PLSX = 0x95B303987A60C71504D99Aa1b13B4DA07b0790ab;
    address public constant PLS = 0xA1077a294dDE1B09bB078844df40758a5D0f9a27;
    address public constant FAVOR_PDAI = 0xBc91E5aE4Ce07D0455834d52a9A4Df992e12FE12;
    address public constant FAVOR_PLSX = 0x47c3038ad52E06B9B4aCa6D672FF9fF39b126806;
    address public constant FAVOR_PLS = 0x30be72a397667FDfD641E3e5Bd68Db657711EB20;
    address public constant PLSFLP = 0xdca85EFDCe177b24DE8B17811cEC007FE5098586;
    address public constant PLSXFLP = 0x24264d580711474526e8F2A8cCB184F6438BB95c;
    address public constant PDAIFLP = 0xA0126Ac1364606BAfb150653c7Bc9f1af4283DFa;

    address[] public dustTokens;
    mapping(address=>bool) public isDustToken;

    receive() external payable {}

    constructor() Ownable(msg.sender) {

        addDustToken(FAVOR_PDAI);
        addDustToken(FAVOR_PLSX);
        addDustToken(FAVOR_PLS);
        addDustToken(PLSX);
        addDustToken(PDAI);
        addDustToken(router.WPLS());

    }

    function getOptimalAddLiquidity(
        address tokenA,
        address tokenB,
        uint    amountADesired
    ) public view returns (uint amountA, uint amountB) {
        address pair = IUniswapV2Factory(router.factory()).getPair(tokenA, tokenB);
        require(pair != address(0), "Pair does not exist");

        (uint112 res0, uint112 res1, ) = IUniswapV2Pair(pair).getReserves();
        (uint reserveA, uint reserveB) =
            tokenA == IUniswapV2Pair(pair).token0()
                ? (res0, res1)
                : (res1, res0);

        uint amountBOptimal = router.quote(amountADesired, reserveA, reserveB);

        return (amountADesired, amountBOptimal);
    }

    function requestFlashLoan(uint256 amount, address favorToken) external {
        address token;
        address lpToken;
        if (favorToken == FAVOR_PLSX) {
            token = PLSX;
            lpToken = PLSXFLP;
        }else if(favorToken == FAVOR_PDAI){
            token = PDAI;
            lpToken = PDAIFLP;
        }else if(favorToken == FAVOR_PLS){
            token = PLS;
            lpToken = PLSFLP;
        }else{
            revert("Flasher: unsupported token");
        }

        bytes memory data = abi.encode(msg.sender, favorToken, lpToken);

        IERC20(favorToken).safeTransferFrom(msg.sender, address(this), amount);
        (, uint256 amtB) = getOptimalAddLiquidity(favorToken, token, amount);

        POOL.flashLoanSimple(
            address(this),
            token,
            amtB,
            data,
            0
        );
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {

        (address user, address favorToken, address lpToken) = abi.decode(params, (address, address, address));

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

    function zap(address token, uint256 amount, uint256 deadline) external payable {
        require(block.timestamp <= deadline, "Zap: deadline out of time");

        if (token == PLS) {
            _zapPLS(amount, deadline);
        } else if (token == PLSX) {
            _zapPLSX(amount, deadline);
        } else if (token == PDAI) {
            _zapPDAI(amount, deadline);
        } else {
            revert("Zap: unsupported");
        }

        _refundDust(msg.sender);
    }

    function _zapPLS(uint256 amount, uint256 dl) internal {
        uint256 half = amount / 2;

        IWPLS(router.WPLS()).deposit{ value: half }();

        uint256 balFavor =_swapAndLog(router.WPLS(), FAVOR_PLS, half, dl);

        _addLiquidityETH(FAVOR_PLS, half, balFavor, address(this), dl);

        uint256 balLP = IERC20(PLSFLP).balanceOf(address(this));
        _depositToStronghold(PLSFLP, balLP);
    }

    function _zapPLSX(uint256 amount, uint256 dl) internal {
        uint256 half = amount / 2;

        IERC20(PLSX).safeTransferFrom(msg.sender, address(this), amount);

        uint256 balFavor =_swapAndLog(PLSX, FAVOR_PLSX, half, dl);
        _addLiquidity(PLSX, FAVOR_PLSX, half, balFavor, address(this), dl);

        uint256 balLP = IERC20(PLSXFLP).balanceOf(address(this));
        _depositToStronghold(PLSXFLP, balLP);
    }

    function _zapPDAI(uint256 amount, uint256 dl) internal {
        uint256 half = amount / 2;

        IERC20(PDAI).safeTransferFrom(msg.sender, address(this), amount);

        uint256 balFavor =_swapAndLog(PDAI, FAVOR_PDAI, half, dl);
        _addLiquidity(PDAI, FAVOR_PDAI, half, balFavor, address(this), dl);

        uint256 balLP = IERC20(PDAIFLP).balanceOf(address(this));
        _depositToStronghold(PDAIFLP, balLP);
    }

    function _swapAndLog(
        address inToken,
        address favorToken,
        uint256 amt,
        uint256 dl
    ) internal returns (uint256){
        IERC20(inToken).approve(address(router), amt);

        address[] memory path = new address[](2);
        path[0] = inToken;
        path[1] = favorToken;

        uint256 before = IERC20(favorToken).balanceOf(address(this));
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amt, 0, path, address(this), dl
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
        router.addLiquidityETH{ value: ethAmt }(
            token,
            tokenAmt,
            0,
            0,
            to,
            dl
        );
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
        IERC20(token).transferFrom(msg.sender, address(this), amountTokenDesired);
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
            (bool sent,) = recipient.call{value: ethBal}("");
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
        for (uint i=0; i<dustTokens.length; i++) {
            if (dustTokens[i] == token) {
                dustTokens[i] = dustTokens[dustTokens.length - 1];
                dustTokens.pop();
                break;
            }
        }
    }

    function adminWithdraw(IERC20 _token, address _to, uint256 _amount) external onlyOwner {
        require(_to != address(0), "Invalid address");
        _token.safeTransfer(_to, _amount);
    }

    function adminWithdrawPLS(address _to, uint256 _amount) external onlyOwner {
        require(_to != address(0), "Invalid address");
        (bool success, ) = _to.call{value: _amount}("");
        require(success, "Transfer failed");
    }
}