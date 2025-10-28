
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import "./usingFetch/usingFetch.sol";
import "./interfaces/IOracle.sol";
import {IMasterOracle} from "./interfaces/IMasterOracle.sol";

contract MinterOracleV2 is UsingFetch, Ownable2Step, IMasterOracle {

    uint256 private constant ONE = 1e18;
    uint256 private constant MAX_DEPTH = 4;

    IUniswapV2Router02 public router;

    enum PricingKind {
        NONE,           // not configured
        TELLOR_SPOT,    // direct Fetch feed "SpotPrice" (base/quote)
        TWAP_IN_BASE    // TWAP in `baseToken` units, then * baseToken USD via recursion
    }

    struct TokenConfig {
        PricingKind kind;
        string tellorBase;     
        address twapOracle;    // IOracle that quotes token in baseToken units
        address baseToken;     // price(token) = TWAP(token in base) * price(base)
        uint48 maxAge;         // staleness guard, seconds 
    }

    struct DexGuard {
        address[] path;   // path[0] MUST be the token being priced; last MUST be USD stable preferably dai on pulse due to largest liquidity
        uint16    maxBps;  // ie 100 == 1%
        bool      enabled;
    }

    mapping(address => DexGuard) public dexGuards;
    mapping(address => TokenConfig) public configs;

    address public constant WPLS = 0xA1077a294dDE1B09bB078844df40758a5D0f9a27;

    event TokenConfigured(address indexed token, PricingKind kind);
    event TokenTwapOracleUpdated(address indexed token, address indexed oracle);
    event TokenTellorPairUpdated(address indexed token, string base);
    event TokenMaxAgeUpdated(address indexed token, uint48 maxAge);

    error NotConfigured(address token);
    error StalePrice(address token);
    error DepthExceeded();

    constructor(address payable _fetchAddress, address _owner, address _router)
        UsingFetch(_fetchAddress)
        Ownable(_owner)
    {
        router = IUniswapV2Router02(_router);
    }

    /// @notice Register or update a token priced directly from Fetch spot feed
    function setTellorSpotToken(
        address token,
        string calldata baseSym,
        uint48 maxAgeSec
    ) external onlyOwner {
        TokenConfig storage c = configs[token];
        c.kind = PricingKind.TELLOR_SPOT;
        c.tellorBase = baseSym;
        c.maxAge = maxAgeSec;
        emit TokenConfigured(token, PricingKind.TELLOR_SPOT);
        emit TokenTellorPairUpdated(token, baseSym);
        emit TokenMaxAgeUpdated(token, maxAgeSec);
    }

    /// @notice Register or update a token priced via TWAP in `baseToken` units, then multiplied by baseToken USD price
    function setTwapInBaseToken(
        address token,
        address oracle,
        address baseToken,
        uint48 maxAgeSec
    ) external onlyOwner {
        require(oracle != address(0), "oracle=0");
        require(baseToken != address(0), "base=0");
        TokenConfig storage c = configs[token];
        c.kind = PricingKind.TWAP_IN_BASE;
        c.twapOracle = oracle;
        c.baseToken = baseToken;
        c.maxAge = maxAgeSec;
        emit TokenConfigured(token, PricingKind.TWAP_IN_BASE);
        emit TokenTwapOracleUpdated(token, oracle);
        emit TokenMaxAgeUpdated(token, maxAgeSec);
    }

    function setDexGuard(
        address token,
        address[] calldata path, // token -> ... -> USD stable, usually token > pls > dai
        uint16 maxBps,
        bool enabled
    ) external onlyOwner {
        require(token != address(0), "token=0");
        require(path.length >= 2, "path short");
        require(path[0] == token, "path[0]!=token");
        require(maxBps <= 1500, "maxBps too high"); 

        DexGuard storage dex = dexGuards[token];

        delete dex.path;
        for (uint i = 0; i < path.length; i++) {
            dex.path.push(path[i]);
        }

        dex.maxBps  = maxBps;
        dex.enabled = enabled;
    }

    function setMaxAge(address token, uint48 maxAgeSec) external onlyOwner {
        configs[token].maxAge = maxAgeSec;
        emit TokenMaxAgeUpdated(token, maxAgeSec);
    }


    /// @notice Returns USD price with 1e18 decimals; reverts if not configured or stale.
    function getLatestPrice(address token) public view returns (uint256) {
        if (token == address(0)) token = WPLS;
        return _priceUSD(token, 0); 
    }

    /// @notice Expose TWAP raw consult 
    function getTokenTWAP(address token) external view returns (uint256) {
        address o = configs[token].twapOracle;
        require(o != address(0), "no twap");
        try IOracle(o).consult(token, 1e18) returns (uint256 twapPrice) {
            return twapPrice;
        } catch {
            revert("TWAP consult failed");
        }
    } 

    function _priceUSD(address token, uint256 depth) internal view returns (uint256) {
        if (depth > MAX_DEPTH) revert DepthExceeded();

        TokenConfig memory c = configs[token];
        if (c.kind == PricingKind.NONE) revert NotConfigured(token);

        uint256 price;

        if (c.kind == PricingKind.TELLOR_SPOT) {
            price = _tellorSpotUSD(c.tellorBase, c.maxAge);
        } else if (c.kind == PricingKind.TWAP_IN_BASE) {
            uint256 twapInBase = _consultTwap(c.twapOracle, token, c.maxAge);
            uint256 baseUSD = _priceUSD(c.baseToken, depth + 1);
            price = (twapInBase * baseUSD) / ONE;
        } else{
            revert NotConfigured(token);
        }

        _enforceDexGuard(token, price);
        return price;
    }

    function _dexUsdPrice(address[] storage path) internal view returns (uint256 px1e18) {
        require(path.length >= 2, "bad path");

        uint8 inDec = IERC20Metadata(path[0]).decimals();
        uint256 amountIn = (inDec >= 18) ? (ONE * (10 ** (inDec - 18))) : (ONE / (10 ** (18 - inDec)));

        uint[] memory amts = router.getAmountsOut(amountIn, _toMem(path));
        uint256 outRaw = amts[amts.length - 1];

        uint8 outDec = IERC20Metadata(path[path.length - 1]).decimals();
        px1e18 = (outDec >= 18) ? (outRaw / (10 ** (outDec - 18))) : (outRaw * (10 ** (18 - outDec)));
    }

    function _toMem(address[] storage s) internal view returns (address[] memory m) {
        m = new address[](s.length);
        for (uint i = 0; i < s.length; i++) m[i] = s[i];
    }

    function _consultTwap(address oracle, address token, uint48 maxAge) internal view returns (uint256) {
        try IOracle(oracle).consult(token, ONE) returns (uint256 out) {
            uint256 last = uint256(IOracle(oracle).blockTimestampLast());
            if (block.timestamp - last > uint256(maxAge)) revert StalePrice(token);
            return out;
        } catch {
            revert("TWAP consult failed");
        }
    }

    function _enforceDexGuard(address token, uint256 usdPrice1e18) internal view {
        DexGuard storage g = dexGuards[token];
        if (!g.enabled) return;

        uint256 dexPx = _dexUsdPrice(g.path);
        uint256 diff  = (usdPrice1e18 > dexPx) ? (usdPrice1e18 - dexPx) : (dexPx - usdPrice1e18);

        require(diff * 10_000 <= dexPx * g.maxBps, "Dex guard: deviation too large");
    }

    function _tellorSpotUSD(string memory baseSym, uint48 maxAge)
        internal
        view
        returns (uint256)
    {
        bytes memory queryData = abi.encode("SpotPrice", abi.encode(baseSym, "usd"));
        bytes32 queryId = keccak256(queryData);

        // 20 Min buffer is recommended to allow time for bad values to be disputed
        (bytes memory _value, uint256 ts) = getDataBefore(queryId, block.timestamp - 20 minutes);
        if (ts == 0) revert("Tellor: no data");
        if (block.timestamp - ts > uint256(maxAge)) revert StalePrice(address(0));
        return abi.decode(_value, (uint256)); 
    }
}
