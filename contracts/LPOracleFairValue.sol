// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./interfaces/IMasterOracle.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

contract LPOracleFairValue {
    IMasterOracle public immutable oracle;

    constructor(address _oracle) {
        oracle = IMasterOracle(_oracle);
    }

    function getUSDPx_Q112(address token) public view returns (uint256) {
        uint256 usdWad = oracle.getLatestPrice(token);         
        return Math.mulDiv(usdWad, 1 << 112, 1e18);   
    }

    /// @dev Fair value LP calculation using geometric mean of forumla
    function lpPriceUSD_Q112(address pair) public view returns (uint256) {
        (uint112 r0, uint112 r1, ) = IUniswapV2Pair(pair).getReserves();
        if (r0 == 0 || r1 == 0) return 0;
        uint256 totalSupply = IUniswapV2Pair(pair).totalSupply();
        require(totalSupply != 0, "LP: ZERO_SUPPLY");

        uint256 sqrtKQ112 = Math.mulDiv(Math.sqrt(uint256(r0) * uint256(r1)), 1 << 112, totalSupply);

        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();

        // USD prices in Q112
        uint256 px0 = getUSDPx_Q112(token0);
        uint256 px1 = getUSDPx_Q112(token1);
        require(px0 != 0 && px1 != 0, "Invalid price");

        uint256 s0 = Math.sqrt(px0);
        uint256 s1 = Math.sqrt(px1);

        uint256 res = Math.mulDiv(sqrtKQ112 * 2, s0, 1 << 56);
        res = Math.mulDiv(res, s1, 1 << 56);
        return res; 
    }

    function lpPriceUSD_WAD(address pair) external view returns (uint256) {
        uint256 q112 = lpPriceUSD_Q112(pair);
        return Math.mulDiv(q112, 1e18, 1 << 112); 
    }

/// @notice Raw redeemable USD per LP in Q112.112 (arithmetic sum of reserves), for sanity check spot price not used in calculations
function redeemableUsdPerLpQ112(address pair) public view returns (uint256) {
    IUniswapV2Pair p = IUniswapV2Pair(pair);
    (uint112 r0, uint112 r1, ) = p.getReserves();
    if (r0 == 0 || r1 == 0) return 0;

    address token0 = p.token0();
    address token1 = p.token1();

    uint256 px0 = getUSDPx_Q112(token0);
    uint256 px1 = getUSDPx_Q112(token1);
    require(px0 != 0 && px1 != 0, "LPOracle: ZERO_TOKEN_PRICE");

    uint256 value0Q112 = Math.mulDiv(uint256(r0), px0, 1e18);
    uint256 value1Q112 = Math.mulDiv(uint256(r1), px1, 1e18);
    uint256 totalUsdQ112 = value0Q112 + value1Q112;

    // Return Q112 value
    return Math.mulDiv(totalUsdQ112, 1e18, p.totalSupply());
}

/// @notice Redeemable USD per LP in WAD (1e18), for sanity check spot price not used in calculations
function redeemableUsdPerLpScaled(address pair) public view returns (uint144) {
    uint256 q112 = redeemableUsdPerLpQ112(pair);
    uint256 scaled = Math.mulDiv(q112, 1e18, 1 << 112);
    return uint144(scaled);
}

}