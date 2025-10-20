//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./interfaces/IFavorToken.sol";
import "@aave/core-v3/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";
import "@aave/core-v3/contracts/interfaces/IPool.sol";

import "@openzeppelin/contracts/access/Ownable2Step.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";

import {KillswitchPausable} from "./KillswitchPausable.sol";
import {Killswitch} from "./Killswitch.sol";


contract LPZapper is Ownable2Step, ReentrancyGuard, KillswitchPausable {
    using SafeERC20 for IERC20;

    address public immutable WPLS;
    IUniswapV2Router02 public immutable router;

    IPool public POOL;

    bool public depositToLending = true;
    address public pendingUser;

    // Treasury Multisig Addresses
    address public team = 0x1EA35487AE62322F61f4C0F639a598d9eEB2F340;
    address public holding = 0x6831f815963FfCe95521271b94164eb4C82e7621;

    address[] public dustTokens;
    mapping(address => bool) public isDustToken;
    mapping(address => address) public favorToToken;
    mapping(address => address) public favorToLp;
    mapping(address => address) public tokenToFavor;


    event NewPOOL(address indexed poolAddress);
    event FavorRemoved(address indexed favorToken);
    event DustTokenAdded(address indexed token);
    event DustTokenRemoved(address indexed token);
    event DepositToStrongholdAllowed(bool allowed);
    event TreasuryUpdated(address indexed newHolding, address indexed newTeam);
    event AdminWithdraw(address indexed token, address indexed to, uint256 amount);
    event FlashLoanExecuted(address indexed user, address indexed lpToken, uint256 lpAmount);
    event TaxCollected(address indexed favor, uint256 taxAmount, uint256 toPool, uint256 toTeam);
    event ActiveFavorTokenSet(address indexed favorToken, address indexed lpToken, address indexed baseToken);
    event TokenZapped(address indexed user, address indexed tokenIn, address indexed favor, uint256 amountIn, uint256 lpAmount);
    event FavorSold(address indexed seller, address indexed receiver, address indexed favor, uint256 amountSold, uint256 baseReceived, uint256 taxPaid);
    event FavorBought(address indexed buyer, address indexed receiver, address indexed baseToken, uint256 amountSpent, uint256 favorReceived);

    receive() external payable {}


    constructor(address _owner, address _router, address _wpls, Killswitch _killswitch) Ownable(_owner) KillswitchPausable(_killswitch) {
        router = IUniswapV2Router02(_router);
        WPLS = _wpls;
    }

    /**
     * create liquidity by requesting flash loan, swapping it into pair  and put LP
     * as collateral
     */
    function requestFlashLoan(uint256 _amount, address _favorToken) external nonReentrant whenNotPaused {
        address token = favorToToken[_favorToken];
        address lpToken = favorToLp[_favorToken];

        require(token != address(0), "Zapper: unsupported token");
        require(lpToken != address(0), "Zapper: unsupported token");

        pendingUser = msg.sender;

        bytes memory data = abi.encode(msg.sender, _favorToken, lpToken);

        IERC20(_favorToken).safeTransferFrom(msg.sender, address(this), _amount);

        (uint112 res0, uint112 res1,) = IUniswapV2Pair(lpToken).getReserves();
        (uint reserveA, uint reserveB) = _favorToken == IUniswapV2Pair(lpToken).token0()
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
    ) external returns (bool) {
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
            block.timestamp
        );

        IERC20(lpToken).forceApprove(address(POOL), lpAmount);

        POOL.supply(lpToken, lpAmount, user, 0);
        POOL.borrow(asset, amount + premium, 2, 0, user);

        IERC20(asset).forceApprove(address(POOL), amount + premium);

        emit FlashLoanExecuted(user, lpToken, lpAmount);

        return true;
    }

    //  zap  token into LP with favor
    function zapToken(address _token, uint _amount, uint256 _deadline) public nonReentrant whenNotPaused {
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        _zapToken(_token, _amount, _deadline);
    }

    function _zapToken(address _token, uint _amount, uint256 _deadline) internal {
        address favor = tokenToFavor[_token];
        require(favor != address(0), "Zap: unsupported");

        address lp = favorToLp[favor];
        require(lp != address(0), "Zap: no lp");

        uint256 half = _amount / 2;

        uint256 balFavor = _swap(_token, favor, half, 0, _deadline);
        IFavorToken(favor).logBuy(msg.sender, balFavor);

        _addLiquidity(_token, favor, half, balFavor, address(this), _deadline);

        uint256 balLP = IERC20(lp).balanceOf(address(this));
        _depositToStronghold(lp, balLP);

        _refundDust(msg.sender);

        emit TokenZapped(msg.sender, _token, favor, _amount, balLP);

    }

    function zapPLS(uint256 _deadline) public payable nonReentrant whenNotPaused {
        //  wrap
        IWETH(WPLS).deposit{value: msg.value}();
        _zapToken(WPLS, uint112(msg.value), _deadline);
    }

    //  wrap swapping -  to make it tax exempt
    function _swap(
        address _in,
        address _out,
        uint256 _amount,
        uint256 _amountOutMin,
        uint256 _deadline
    ) internal returns (uint256) {
        IERC20(_in).forceApprove(address(router), _amount);

        address[] memory path = new address[](2);
        path[0] = _in;
        path[1] = _out;

        uint256 before = IERC20(_out).balanceOf(address(this));
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amount,
            _amountOutMin,
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
     * Either deposit 80% to lending pool for treasury multisig or send in base token to liquidator reserve
     * 20% always gets sent in base token to team multisig
     */
    function _depositToStrongholdForTreasury(address token, uint256 amount) internal {
        uint256 treasuryAmt = (amount * 20) / 100;
        uint256 holdingAmt = amount - treasuryAmt;

        if(depositToLending){
            IERC20(token).forceApprove(address(POOL), holdingAmt);
            POOL.supply(token, holdingAmt, holding, 0);
        }else{
            IERC20(token).safeTransfer(holding, holdingAmt);
        }   

        IERC20(token).safeTransfer(team, treasuryAmt);  

        emit TaxCollected(token, amount, holdingAmt, treasuryAmt);
    }

    /**
     * sell favor with taxation.   tax is sent to treasury in  base token
     */
    function sell(address _favor, uint256 _amount, uint256 _amountOutMin, uint256 _deadline) public {
        sellTo(msg.sender, _favor, _amount, _amountOutMin, _deadline);
    }

    function sellTo(address _receiver, address _favor, uint256 _amount, uint256 _amountOutMin, uint256 _deadline) public nonReentrant whenNotPaused {

        address base = favorToToken[_favor];
        require(base != address(0), "Zapper: unsupported token");
        require(_receiver != address(0), "Cannot send to address(0)");

        IERC20(_favor).safeTransferFrom(msg.sender, address(this), _amount);

        uint256 tax = 0;
        // is seller taxed?  sell 50% to treasury
        if (!IFavorToken(_favor).isTaxExempt(msg.sender)) {
            // seller is taxed.   sell 50%  to treasury
            tax = IFavorToken(_favor).calculateTax(_amount);
            uint256 taxSold = _swap(_favor, base, tax, 0, _deadline);
            _depositToStrongholdForTreasury(base, taxSold);
        }

        uint256 userSold = _swap(_favor, base, _amount - tax, _amountOutMin, _deadline);

        if (base == WPLS) {       
            IWETH(WPLS).withdraw(userSold);      
            (bool ok,) = _receiver.call{value: userSold}("");
            require(ok, "Zapper: PLS transfer failed");
        } else {
            IERC20(base).safeTransfer(_receiver, userSold);
        }

        emit FavorSold(msg.sender, _receiver, _favor, _amount, userSold, tax);

    }

    /**
     * buy favor with base token.   rewards are minted
     */
    function buy(address _baseToken, uint256 _amount, uint256 _amountOutMin, uint256 _deadline) public payable {
        buyTo(msg.sender, _baseToken, _amount, _amountOutMin, _deadline);
    }

    function buyTo(address _receiver, address _base, uint256 _amount, uint256 _amountOutMin, uint256 _deadline) public payable nonReentrant whenNotPaused {

        address favor = tokenToFavor[_base];
        require(favor != address(0), "Zapper: unsupported token");
        require(_receiver != address(0), "Cannot send to address(0)");
        require(_amount == 0 || msg.value == 0, "Provide either _amount or msg.value");

        uint256 input;
        if (_base == WPLS && msg.value > 0) {
            // Native path: wrap PLS → WPLS and use it as swap input
            IWETH(WPLS).deposit{value: msg.value}();
            input = msg.value;
        } else {
            // ERC20 path
            IERC20(_base).safeTransferFrom(msg.sender, address(this), _amount);
            input = _amount;
        }

        uint256 bought = _swap(_base, favor, input, _amountOutMin, _deadline);

        //  return token balance to _receiver
        IERC20(favor).safeTransfer(_receiver, bought);

        //  log buy and mint bonuses for everybody
        IFavorToken(favor).logBuy(_receiver, bought);

        emit FavorBought(msg.sender, _receiver, _base, input, bought);
    }

    function _addLiquidity(
        address a,
        address b,
        uint256 aAmt,
        uint256 bAmt,
        address to,
        uint256 dl
    ) internal {
        IERC20(a).forceApprove(address(router), aAmt);
        IERC20(b).forceApprove(address(router), bAmt);
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
    ) external nonReentrant whenNotPaused {
        IERC20(tokenA).safeTransferFrom(msg.sender, address(this), amountADesired);
        IERC20(tokenB).safeTransferFrom(msg.sender, address(this), amountBDesired);

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

        _refundDust(msg.sender);
    }

    //  wrapper for the router call to aavoid  coin taxation
    function addLiquidityETH(
        address _token,
        uint _amountTokenDesired,
        uint _amountTokenMin,
        uint _amountETHMin,
        address _to,
        uint _deadline
    ) external payable nonReentrant whenNotPaused {
        IERC20(_token).safeTransferFrom(
            msg.sender,
            address(this),
            _amountTokenDesired
        );
        IERC20(_token).forceApprove(address(router), _amountTokenDesired);

        router.addLiquidityETH{value: msg.value}(
            _token,
            _amountTokenDesired,
            _amountTokenMin,
            _amountETHMin,
            _to,
            _deadline
        );
        _refundDust(msg.sender);
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

    function setPool(IPool _pool) external onlyOwner {
        require(address(_pool) != address(0), "Must be a valid address");
        POOL = _pool;
        emit NewPOOL(address(_pool));
    }

    function setTreasury(address _holding, address _team) external onlyOwner {
        require(_holding != address(0), "Invalid Holding address");
        require(_team != address(0), "Invalid Team address");
        holding = _holding;
        team = _team;
        emit TreasuryUpdated(_holding, _team);
    }

    function addDustToken(address token) public onlyOwner {
        require(!isDustToken[token], "dust token already added");
        isDustToken[token] = true;
        dustTokens.push(token);
        emit DustTokenAdded(token);
    }

    function removeDustToken(address token) external onlyOwner {
        require(isDustToken[token], "dust token not registered");
        isDustToken[token] = false;
        for (uint i = 0; i < dustTokens.length; i++) {
            if (dustTokens[i] == token) {
                dustTokens[i] = dustTokens[dustTokens.length - 1];
                dustTokens.pop();
                break;
            }
        }
        emit DustTokenRemoved(token);
    }

    function adminWithdraw(
        IERC20 _token,
        address _to,
        uint256 _amount
    ) external onlyOwner {
        require(_to != address(0), "Invalid address");
        _token.safeTransfer(_to, _amount);
        emit AdminWithdraw(address(_token), _to, _amount);
    }

    function adminWithdrawPLS(address _to, uint256 _amount) external onlyOwner {
        require(_to != address(0), "Invalid address");
        (bool success,) = _to.call{value: _amount}("");
        require(success, "Transfer failed");
        emit AdminWithdraw(address(address(0)), _to, _amount);
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
        require(favorToLp[_favor] == address(0), "Favor already registered");
        require(tokenToFavor[_token] == address(0), "Token already registered");

        // LP shall match,   HAL-13
        address t0 = IUniswapV2Pair(_lp).token0();
        address t1 = IUniswapV2Pair(_lp).token1();
        require(t0 == _favor && t1 == _token || t0 == _token && t1 == _favor, "LP token mismatch");

        favorToToken[_favor] = _token;
        favorToLp[_favor] = _lp;
        tokenToFavor[_token] = _favor;

        addDustToken(_favor);
        addDustToken(_token);
        emit ActiveFavorTokenSet(_favor, _lp, _token);
    }

    function removeFavorToken(address _favor) external onlyOwner {
        require(_favor != address(0), "Invalid address");

        delete (tokenToFavor[favorToToken[_favor]]);
        delete (favorToLp[_favor]);
        delete (favorToToken[_favor]);
        emit FavorRemoved(_favor);
    }

    function setDepositToStronghold(bool allowed) external onlyOwner {
        depositToLending = allowed;
        emit DepositToStrongholdAllowed(allowed);
    }

    // Helpers for UI, plug and play from before 
    function uiAmountsOut(
        uint256 amountIn,
        address[] calldata path
    ) external view returns (uint256[] memory amounts) {
        require(amountIn > 0 && path.length >= 2, "Invalid inputs"); 
        try router.getAmountsOut(amountIn, path) returns (uint[] memory amts) {
            return (amts);
        } catch {
            revert("Output not found");
        }
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
}
