
// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@uniswap/v2-periphery/contracts/libraries/UniswapV2OracleLibrary.sol";

import "./Epoch.sol";
import "./libraries/HomoraMath.sol";
import "./interfaces/IMasterOracle.sol";

/// @dev Legacy Uni V2 TWAP oracle for LP tokens with reserves TWAP

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
        require(_period >= 15 minutes && _period <= 24 hours, "_period: out of range");

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
    function setMaxPriceCap(uint256 _lpPriceCap) external onlyApproved {
        lpPriceCap  = _lpPriceCap;
        emit PriceCapUpdated(_lpPriceCap);
    }

    /// @notice Set Master oracle contract for USD price feeds of individual tokens in LP
    function setMasterOracle(address _oracle) external onlyApproved {
        masterOracle  = IMasterOracle(_oracle);
        emit OracleUpdated(_oracle);
    }

}