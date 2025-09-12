// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "./Epoch.sol";
import "@uniswap/v2-periphery/contracts/libraries/UniswapV2OracleLibrary.sol";

/// @dev Legacy Uni V2 TWAP oracle for individual tokens

// fixed window oracle that recomputes the average price for the entire period once every period
// note that the price average is only guaranteed to be over at least 1 period, but may be over a longer period
contract Oracle is Epoch {
    using FixedPoint for *;

    /* ========== STATE VARIABLES ========== */

    // uniswap
    address public token0;
    address public token1;
    IUniswapV2Pair public pair;

    // oracle
    uint32 public blockTimestampLast;
    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public maxPriceCap;
    FixedPoint.uq112x112 public price0Average;
    FixedPoint.uq112x112 public price1Average;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        IUniswapV2Pair _pair,
        uint256 _period,
        uint256 _startTime,
        uint256 _priceCap
    ) Epoch(_period, _startTime, 0) {
        require(_period >= 15 minutes && _period <= 24 hours, '_period: out of range');
        pair = _pair;
        token0 = pair.token0();
        token1 = pair.token1();
        maxPriceCap = _priceCap;
        price0CumulativeLast = pair.price0CumulativeLast(); // fetch the current accumulated price value (1 / 0)
        price1CumulativeLast = pair.price1CumulativeLast(); // fetch the current accumulated price value (0 / 1)
        uint112 reserve0;
        uint112 reserve1;
        (reserve0, reserve1, blockTimestampLast) = pair.getReserves();
        require(reserve0 != 0 && reserve1 != 0, "Oracle: NO_RESERVES"); // ensure that there's liquidity in the pair
    }

    /* ========== MUTABLE FUNCTIONS ========== */

    /// @dev Updates TWAP price from Uniswap 
    function update() public checkEpoch {
        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) =
            UniswapV2OracleLibrary.currentCumulativePrices(address(pair));

        uint32 timeElapsed;
        unchecked {
            // Overflow desired wrapped in unchecked
            timeElapsed = blockTimestamp - blockTimestampLast;
        }
        if (timeElapsed == 0) return; // prevent divide-by-zero

        uint256 price0Delta;
        uint256 price1Delta;
        unchecked {
            // Overflow desired wrapped in unchecked
            price0Delta = price0Cumulative - price0CumulativeLast;
            price1Delta = price1Cumulative - price1CumulativeLast;
        }

        // average = (cumulativeDelta / timeElapsed) in uq112x112
        price0Average = FixedPoint.uq112x112(uint224(price0Delta / timeElapsed));
        price1Average = FixedPoint.uq112x112(uint224(price1Delta / timeElapsed));

        price0CumulativeLast = price0Cumulative;
        price1CumulativeLast = price1Cumulative;
        blockTimestampLast = blockTimestamp;

        emit Updated(price0Cumulative, price1Cumulative);
    }

    /// @notice Will always return 0 before update has been called successfully for the first time.
    function consult(address _token, uint256 _amountIn) external view returns (uint256 amountOut) {

        if (_token == token0) {
            amountOut = uint256(price0Average.mul(_amountIn).decode144()); // Uses FixedPoint library for mul of uq112x112
        } else {
            require(_token == token1, "Oracle: INVALID_TOKEN");
            amountOut = uint256(price1Average.mul(_amountIn).decode144());
        }

        if (maxPriceCap > 0 && amountOut > maxPriceCap) {
            amountOut = maxPriceCap;
        }
    }

    /// @notice Returns rolling TWAP price which is more likely to be prone to short term price fluctuations. Only used on UI for informational purposes.
    function twap(address _token, uint256 _amountIn) external view returns (uint256 _amountOut) {
        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) =
            UniswapV2OracleLibrary.currentCumulativePrices(address(pair));

        uint32 timeElapsed;
        unchecked { timeElapsed = blockTimestamp - blockTimestampLast; } // Overflow desired wrapped in unchecked
        if (timeElapsed == 0) return 0;

        if (_token == token0) {
            uint256 price0Delta;
            unchecked { price0Delta = price0Cumulative - price0CumulativeLast; }
            _amountOut = uint256(
                FixedPoint.uq112x112(uint224(price0Delta / timeElapsed)).mul(_amountIn).decode144()
            );
        } else if (_token == token1) {
            uint256 price1Delta;
            unchecked { price1Delta = price1Cumulative - price1CumulativeLast; }
            _amountOut = uint256(
                FixedPoint.uq112x112(uint224(price1Delta / timeElapsed)).mul(_amountIn).decode144()
            );
        } else {
            revert("Oracle: INVALID_TOKEN");
        }

        if (maxPriceCap > 0 && _amountOut > maxPriceCap) {
            _amountOut = maxPriceCap;
        }
    }

    function setMaxPriceCap(uint256 _cap) external onlyApproved {
        require(_cap > 0, "Cap must be positive");
        maxPriceCap = _cap;
        emit MaxPriceCapSet(_cap);
    }

    event Updated(uint256 price0CumulativeLast, uint256 price1CumulativeLast);
    event MaxPriceCapSet(uint256 cap);
}