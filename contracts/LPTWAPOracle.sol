
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@uniswap/v2-periphery/contracts/libraries/UniswapV2OracleLibrary.sol";

import "./interfaces/IMasterOracle.sol";

/// @dev Legacy Uni V2 TWAP oracle for LP tokens with reserves TWAP

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}

/**
 * @dev Wrappers over Solidity's arithmetic operations.
 */
library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            uint256 c = a + b;
            if (c < a) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the substraction of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b > a) return (false, 0);
            return (true, a - b);
        }
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
            // benefit is lost if 'b' is also tested.
            // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
            if (a == 0) return (true, 0);
            uint256 c = a * b;
            if (c / a != b) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the division of two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a / b);
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a % b);
        }
    }

    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a - b;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        return a * b;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator.
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return a / b;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return a % b;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {trySub}.
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b <= a, errorMessage);
            return a - b;
        }
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a / b;
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting with custom message when dividing by zero.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryMod}.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a % b;
        }
    }
}

library HomoraMath {
  using SafeMath for uint;

  function divCeil(uint lhs, uint rhs) internal pure returns (uint) {
    return lhs.add(rhs).sub(1) / rhs;
  }

  function fmul(uint lhs, uint rhs) internal pure returns (uint) {
    return lhs.mul(rhs) / (2**112);
  }

  function fdiv(uint lhs, uint rhs) internal pure returns (uint) {
    return lhs.mul(2**112) / rhs;
  }

  // implementation from https://github.com/Uniswap/uniswap-lib/commit/99f3f28770640ba1bb1ff460ac7c5292fb8291a0
  // original implementation: https://github.com/abdk-consulting/abdk-libraries-solidity/blob/master/ABDKMath64x64.sol#L687
  function sqrt(uint x) internal pure returns (uint) {
    if (x == 0) return 0;
    uint xx = x;
    uint r = 1;

    if (xx >= 0x100000000000000000000000000000000) {
      xx >>= 128;
      r <<= 64;
    }

    if (xx >= 0x10000000000000000) {
      xx >>= 64;
      r <<= 32;
    }
    if (xx >= 0x100000000) {
      xx >>= 32;
      r <<= 16;
    }
    if (xx >= 0x10000) {
      xx >>= 16;
      r <<= 8;
    }
    if (xx >= 0x100) {
      xx >>= 8;
      r <<= 4;
    }
    if (xx >= 0x10) {
      xx >>= 4;
      r <<= 2;
    }
    if (xx >= 0x8) {
      r <<= 1;
    }

    r = (r + x / r) >> 1;
    r = (r + x / r) >> 1;
    r = (r + x / r) >> 1;
    r = (r + x / r) >> 1;
    r = (r + x / r) >> 1;
    r = (r + x / r) >> 1;
    r = (r + x / r) >> 1; // Seven iterations should be enough
    uint r1 = x / r;
    return (r < r1 ? r : r1);
  }
}


/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract Operator is Context, Ownable {
    address private _operator;

    event OperatorTransferred(address indexed previousOperator, address indexed newOperator);

    constructor() {
        _operator = _msgSender();
        emit OperatorTransferred(address(0), _operator);
    }

    function operator() public view returns (address) {
        return _operator;
    }

    modifier onlyOperator() {
        require(_operator == msg.sender, "operator: caller is not the operator");
        _;
    }

    function isOperator() public view returns (bool) {
        return _msgSender() == _operator;
    }

    function transferOperator(address newOperator_) public onlyOwner {
        _transferOperator(newOperator_);
    }

    function _transferOperator(address newOperator_) internal {
        require(newOperator_ != address(0), "operator: zero address given for new operator");
        emit OperatorTransferred(address(0), newOperator_);
        _operator = newOperator_;
    }
}

contract Epoch is Operator {
    using SafeMath for uint256;

    uint256 private period;
    uint256 private startTime;
    uint256 private lastEpochTime;
    uint256 private epoch;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        uint256 _period,
        uint256 _startTime,
        uint256 _startEpoch
    ) {
        period = _period;
        startTime = _startTime;
        epoch = _startEpoch;
        lastEpochTime = startTime.sub(period);
    }

    /* ========== Modifier ========== */

    modifier checkStartTime {
        require(block.timestamp >= startTime, 'Epoch: not started yet');

        _;
    }

    modifier checkEpoch {
        uint256 _nextEpochPoint = nextEpochPoint();
        if (block.timestamp < _nextEpochPoint) {
            require(msg.sender == operator(), 'Epoch: only operator allowed for pre-epoch');
            _;
        } else {
            _;

            for (;;) {
                lastEpochTime = _nextEpochPoint;
                ++epoch;
                _nextEpochPoint = nextEpochPoint();
                if (block.timestamp < _nextEpochPoint) break;
            }
        }
    }

    /* ========== VIEW FUNCTIONS ========== */

    function getCurrentEpoch() public view returns (uint256) {
        return epoch;
    }

    function getPeriod() public view returns (uint256) {
        return period;
    }

    function getStartTime() public view returns (uint256) {
        return startTime;
    }

    function getLastEpochTime() public view returns (uint256) {
        return lastEpochTime;
    }

    function nextEpochPoint() public view returns (uint256) {
        return lastEpochTime.add(period);
    }

    /* ========== GOVERNANCE ========== */

    function setPeriod(uint256 _period) external onlyOperator {
        require(_period >= 1 hours && _period <= 48 hours, '_period: out of range');
        period = _period;
    }

    function setEpoch(uint256 _epoch) external onlyOperator {
        epoch = _epoch;
    }
}
contract LPOracle is Epoch {
    using SafeMath for uint256;
    using FixedPoint for *;
    using HomoraMath for uint;

    /* ========== IMMUTABLES ========== */
    IUniswapV2Pair public immutable pair;
    address       public immutable token0;
    address       public immutable token1;

    /* ========== CUMULATIVE STATE ========== */
    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint32  public blockTimestampLast;

    uint256 public kCumulativeLast;
    uint32  public kTimestampLast;
    uint256 public lastSqrtK;

    uint256 public usd0CumulativeLast;
    uint256 public usd1CumulativeLast;
    uint32  public usdTimestampLast;

    IMasterOracle public masterOracle;

    /* ========== TWAP OUTPUTS ========== */
    FixedPoint.uq112x112 public price0Average;
    FixedPoint.uq112x112 public price1Average;
    FixedPoint.uq112x112 public kAverage;
    FixedPoint.uq112x112 public usd0Average;
    FixedPoint.uq112x112 public usd1Average;

    /* ========== CAPS ========== */
    uint256 public lastLpPrice;
    uint256 public lpPriceCap;

    event Updated(
        uint256 price0Cumulative,
        uint256 price1Cumulative,
        uint256 kCumulative,
        uint256 usd0Cumulative,
        uint256 usd1Cumulative,
        uint32  timestamp
    );
    event PriceCapUpdated(uint256 newPriceCap);
    event OracleUpdated(address indexed newOracle);

    constructor(
        IUniswapV2Pair _pair,
        IMasterOracle _masterOracle,
        uint256 _period,
        uint256 _startTime,
        uint256 _priceCap
    ) Epoch(_period, _startTime, 0) {
        require(_period >= 1 hours && _period <= 48 hours, "_period: out of range");

        pair            = _pair;
        token0          = _pair.token0();
        token1          = _pair.token1();
        masterOracle    = _masterOracle;
        lpPriceCap      = _priceCap;

        // seed Uniswap price cumulatives + timestamp
        (uint256 p0C, uint256 p1C, uint32 ts) = UniswapV2OracleLibrary
            .currentCumulativePrices(address(pair));
        price0CumulativeLast = p0C;
        price1CumulativeLast = p1C;
        blockTimestampLast   = ts;

        // seed √K cumulative + lastSqrtK at current block time
        uint32 nowTs = uint32(block.timestamp);
        kTimestampLast     = nowTs;
        (uint112 r0, uint112 r1,) = _pair.getReserves();
        uint256 initialSqrtK = HomoraMath
            .sqrt(uint256(r0).mul(r1))
            .fdiv(_pair.totalSupply());
        kCumulativeLast    = initialSqrtK.mul(nowTs);
        lastSqrtK          = initialSqrtK;

        // seed USD feed cumulatives at current block time
        usdTimestampLast   = nowTs;
        uint256 initialU0  = masterOracle.getLatestPrice(token0);
        uint256 initialU1  = masterOracle.getLatestPrice(token1);
        usd0CumulativeLast = initialU0.mul(nowTs);
        usd1CumulativeLast = initialU1.mul(nowTs);
    }

    /// @notice Update TWAPs: Uniswap prices, √K, and USD feeds
    function update() external checkEpoch {
        // 1) token0/token1 price TWAPs (Uniswap cumulative)
        {
            (uint256 p0C, uint256 p1C, uint32 blockTs) = UniswapV2OracleLibrary
                .currentCumulativePrices(address(pair));
            uint32 dt = blockTs - blockTimestampLast;
            require(dt > 0, "Oracle: ZERO_TIME");

            price0Average = FixedPoint.uq112x112(
                uint224((p0C - price0CumulativeLast) / dt)
            );
            price1Average = FixedPoint.uq112x112(
                uint224((p1C - price1CumulativeLast) / dt)
            );

            price0CumulativeLast = p0C;
            price1CumulativeLast = p1C;
            blockTimestampLast   = blockTs;
        }

                // 2) √K TWAP via two-segment integration
        {
            // get reserves + last-reserve-update timestamp
            (uint112 r0, uint112 r1, uint32 tsReserve) = pair.getReserves();
            uint32 nowTs = uint32(block.timestamp);

            // spot √K (Q112.112)
            uint256 sqrtKNow = HomoraMath
                .sqrt(uint256(r0).mul(r1))
                .fdiv(pair.totalSupply());

            // total time since last oracle update
            uint32 dtFull = nowTs - kTimestampLast;
            require(dtFull > 0, "Oracle: ZERO_TIME");

            // split into before/after reserve-change
            uint32 dt1;
            uint32 dt2;
            if (tsReserve > kTimestampLast) {
                dt1 = tsReserve - kTimestampLast;
                dt2 = nowTs - tsReserve;
            } else {
                dt1 = dtFull;
                dt2 = 0;
            }

            // patch cumulative: old√K * dt1 + new√K * dt2
            uint256 kC = kCumulativeLast
                .add(lastSqrtK.mul(dt1))
                .add(sqrtKNow.mul(dt2));

            // compute TWAP over the full window
            kAverage = FixedPoint.uq112x112(
                uint224((kC - kCumulativeLast) / dtFull)
            );

            kCumulativeLast = kC;
            kTimestampLast  = nowTs;
            lastSqrtK       = sqrtKNow;
        }

        // 3) USD per-token TWAPs (custom feed)
        {
            uint32 nowTsU = uint32(block.timestamp);
            uint256 u0 = masterOracle.getLatestPrice(token0);
            uint256 u1 = masterOracle.getLatestPrice(token1);
            uint32 dtU = nowTsU - usdTimestampLast;
            require(dtU > 0, "Oracle: ZERO_TIME");

            uint256 newUsd0C = usd0CumulativeLast.add(u0.mul(dtU));
            uint256 newUsd1C = usd1CumulativeLast.add(u1.mul(dtU));

            uint256 avg0Raw = (newUsd0C - usd0CumulativeLast) / dtU;
            uint256 avg1Raw = (newUsd1C - usd1CumulativeLast) / dtU;

            uint256 avg0Q112 = avg0Raw.mul(2**112).div(1e18);
            uint256 avg1Q112 = avg1Raw.mul(2**112).div(1e18);

            usd0Average = FixedPoint.uq112x112(uint224(avg0Q112));
            usd1Average = FixedPoint.uq112x112(uint224(avg1Q112));

            usd0CumulativeLast = newUsd0C;
            usd1CumulativeLast = newUsd1C;
            usdTimestampLast   = nowTsU;
        }

        // 4) LP price jump cap (freeze if > LPPriceCap × last)
        {
            uint256 sqrt0 = HomoraMath.sqrt(uint256(usd0Average._x));
            uint256 sqrt1 = HomoraMath.sqrt(uint256(usd1Average._x));
            uint256 kx    = uint256(kAverage._x);
            uint256 part  = kx.mul(2).mul(sqrt0).div(2**56);
            uint256 lpQ112= part.mul(sqrt1).div(2**56);
            uint256 newLpPrice = lpQ112.mul(1e18) >> 112;

            if (lastLpPrice == 0 || lpPriceCap == 0) {
                lastLpPrice = newLpPrice;
            } else {
                uint256 maxAllowed = lastLpPrice.mul(lpPriceCap).div(1e18);
                if (newLpPrice <= maxAllowed) {
                    lastLpPrice = newLpPrice;
                }
            }
        }

        emit Updated(
            price0CumulativeLast,
            price1CumulativeLast,
            kCumulativeLast,
            usd0CumulativeLast,
            usd1CumulativeLast,
            blockTimestampLast
        );
    }

    /// @notice Consult TWAP: USD per unit of token0, token1 (18-decimals) or LP
    /// @dev Deployer must call update() first after deployment or this will always return 0
    function consult(address _token, uint256 _amountIn)
        external view
        returns (uint256 amountOut)
    {
        if (_token == token0) {
            amountOut = uint256(price0Average.mul(_amountIn).decode144());
        } else if (_token == token1) {
            amountOut = uint256(price1Average.mul(_amountIn).decode144());
        } else if (_token == address(pair)) {
            amountOut = lastLpPrice;
        } else {
            revert("Oracle: INVALID_TOKEN");
        }

    }

    /// @notice Raw redeemable USD per LP in Q112.112
    function redeemableUsdPerLpQ112() public view returns (uint256) {
        (uint112 r0, uint112 r1,) = pair.getReserves();
        uint256 px0 = uint256(usd0Average._x);
        uint256 px1 = uint256(usd1Average._x);
        uint256 totalUsdQ = uint256(r0).mul(px0).add(uint256(r1).mul(px1));
        return totalUsdQ.div(pair.totalSupply());
    }

    /// @notice Redeemable USD per LP scaled by 1e18
    function redeemableUsdPerLpScaled() public view returns (uint144) {
        uint256 q112 = redeemableUsdPerLpQ112();
        uint256 scaled= q112.mul(1e18) >> 112;
        return uint144(scaled);
    }

    /// @notice Set LP price update jump cap ie. 2e18 = 2x lastLpPrice
    function setMaxPriceCap(uint256 _lpPriceCap) external onlyOwner {
        lpPriceCap  = _lpPriceCap;
        emit PriceCapUpdated(_lpPriceCap);
    }

    /// @notice Set Master oracle contract for USD price feeds of individual tokens in LP
    function setMasterOracle(address _oracle) external onlyOwner {
        masterOracle  = IMasterOracle(_oracle);
        emit OracleUpdated(_oracle);
    }
}