
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";

import "./usingFetch/usingFetch.sol";
import "./interfaces/IOracle.sol";
import {IMasterOracle} from "./interfaces/IMasterOracle.sol";

contract MinterOracleV2 is UsingFetch, Ownable2Step, IMasterOracle {

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

    mapping(address => TokenConfig) public configs;

    address public constant WPLS = 0xA1077a294dDE1B09bB078844df40758a5D0f9a27;

    event TokenConfigured(address indexed token, PricingKind kind);
    event TokenTwapOracleUpdated(address indexed token, address indexed oracle);
    event TokenTellorPairUpdated(address indexed token, string base);
    event TokenMaxAgeUpdated(address indexed token, uint48 maxAge);

    constructor(address payable _fetchAddress, address _owner)
        UsingFetch(_fetchAddress)
        Ownable(_owner)
    {}

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
        address baseToken
    ) external onlyOwner {
        require(oracle != address(0), "oracle=0");
        require(baseToken != address(0), "base=0");
        TokenConfig storage c = configs[token];
        c.kind = PricingKind.TWAP_IN_BASE;
        c.twapOracle = oracle;
        c.baseToken = baseToken;
        emit TokenConfigured(token, PricingKind.TWAP_IN_BASE);
        emit TokenTwapOracleUpdated(token, oracle);
        emit TokenMaxAgeUpdated(token, 0);
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

    error NotConfigured(address token);
    error StalePrice(address token);
    error DepthExceeded();

    uint256 private constant ONE = 1e18;
    uint256 private constant MAX_DEPTH = 4; 

    function _priceUSD(address token, uint256 depth) internal view returns (uint256) {
        if (depth > MAX_DEPTH) revert DepthExceeded();

        TokenConfig memory c = configs[token];
        if (c.kind == PricingKind.NONE) revert NotConfigured(token);

        if (c.kind == PricingKind.TELLOR_SPOT) {
            return _tellorSpotUSD(c.tellorBase, c.maxAge);
        }

        // TWAP_IN_BASE: price(token) = twap(token->base) * price(base)
        if (c.kind == PricingKind.TWAP_IN_BASE) {
            uint256 twapInBase = _consultTwap(c.twapOracle, token);
            uint256 baseUSD = _priceUSD(c.baseToken, depth + 1);
            return (twapInBase * baseUSD) / ONE;
        }

        revert NotConfigured(token);
    }

    function _consultTwap(address oracle, address token) internal view returns (uint256) {
        try IOracle(oracle).consult(token, ONE) returns (uint256 out) {
            return out;
        } catch {
            revert("TWAP consult failed");
        }
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
