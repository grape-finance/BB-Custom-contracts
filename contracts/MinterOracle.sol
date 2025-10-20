// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import "./usingFetch/usingFetch.sol";
import "./interfaces/IOracle.sol";
import {IMasterOracle} from "./interfaces/IMasterOracle.sol";

contract MinterOracle is UsingFetch, Ownable2Step,  IMasterOracle {

    //fetch oracle feed testnet 0xe5284f722a509659ec70aa236BA08E10B263bCB2
    //fetch oracle feed mainnet 0xCe9DEa26eB6bEaEc73CFf3BACdF3F9e42BB89951
    uint256 constant ONE = 1e18;           
    uint256 constant TWO_PERCENT = 200;   

    IUniswapV2Router02 public immutable router;

    uint256 public maxBps = 500;

    address public constant wpls = 0xA1077a294dDE1B09bB078844df40758a5D0f9a27;
    address public constant plsx = 0x95B303987A60C71504D99Aa1b13B4DA07b0790ab;
    address public constant pdai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant dai = 0xefD766cCb38EaF1dfd701853BFCe31359239F305;

    address public constant fpls = 0x30be72a397667FDfD641E3e5Bd68Db657711EB20;
    address public constant fplsx = 0x47c3038ad52E06B9B4aCa6D672FF9fF39b126806;
    address public constant fpdai = 0xBc91E5aE4Ce07D0455834d52a9A4Df992e12FE12;

    address public constant fplsLP = 0xdca85EFDCe177b24DE8B17811cEC007FE5098586;
    address public constant fplsxLP = 0x24264d580711474526e8F2A8cCB184F6438BB95c;
    address public constant fpdaiLP = 0xA0126Ac1364606BAfb150653c7Bc9f1af4283DFa;


    mapping(address => address) public priceOracles;

    constructor(address payable _fetchAddress, address _owner, address _router) UsingFetch(_fetchAddress) Ownable(_owner) 
    {
        router = IUniswapV2Router02(_router);
    }

    function getLatestPrice(address _token) public view returns(uint256) {
        
        if (_token == address(0) || _token == wpls) return getPlsSpotPrice();
        if (_token == plsx)     return getPlsxSpotPrice();
        if (_token == dai)      return getDaiSpotPrice();
        if (_token == pdai)     return getPdaiSpotPrice();
        if (_token == fpls)     return getfPLSSpotPrice();
        if (_token == fplsx)    return getfPLSXSpotPrice();
        if (_token == fpdai)    return getfPDAISpotPrice();
        if (_token == fplsLP)   return getTokenTWAP(fplsLP);
        if (_token == fplsxLP)  return getTokenTWAP(fplsxLP);
        if (_token == fpdaiLP)  return getTokenTWAP(fpdaiLP);

        return 0;
    }
    
    function getPlsSpotPrice() public view returns(uint256) {
    
      bytes memory _queryData = abi.encode("SpotPrice", abi.encode("pls", "usd"));
      bytes32 _queryId = keccak256(_queryData);
      
      (bytes memory _value, uint256 _timestampRetrieved) =
          getDataBefore(_queryId, block.timestamp - 20 minutes);
      if (_timestampRetrieved == 0) return 0;
      require(block.timestamp - _timestampRetrieved < 24 hours, "Data timestamp is more than 24 hours.");

      uint256 fetchPrice = abi.decode(_value, (uint256));

      address[] memory path = new address[](2);
      path[0] = wpls;
      path[1] = dai; 
      uint256 dexPrice = _dexPrice(path);         

      uint256 diff = _absDiff(fetchPrice, dexPrice);
      require(diff * 10_000 <= dexPrice * maxBps, "Dex guard: deviation too large");

      return fetchPrice;
    }

    function getPlsxSpotPrice() public view returns(uint256) {
    
      bytes memory _queryData = abi.encode("SpotPrice", abi.encode("plsx", "usd"));
      bytes32 _queryId = keccak256(_queryData);
      
      (bytes memory _value, uint256 _timestampRetrieved) =
          getDataBefore(_queryId, block.timestamp - 20 minutes);
      if (_timestampRetrieved == 0) return 0;
      require(block.timestamp - _timestampRetrieved < 24 hours, "Data timestamp is more than 24 hours.");

      uint256 fetchPrice = abi.decode(_value, (uint256));

      address[] memory path = new address[](3);
      path[0] = plsx;
      path[1] = wpls;
      path[2] = dai;
      uint256 dexPrice = _dexPrice(path);        

      uint256 diff = _absDiff(fetchPrice, dexPrice);
      require(diff * 10_000 <= dexPrice * maxBps, "Dex guard: deviation too large");

      return fetchPrice;
    }

    function getDaiSpotPrice() public view returns(uint256) {
    
      bytes memory _queryData = abi.encode("SpotPrice", abi.encode("dai", "usd"));
      bytes32 _queryId = keccak256(_queryData);
      
      (bytes memory _value, uint256 _timestampRetrieved) =
          getDataBefore(_queryId, block.timestamp - 20 minutes);
      if (_timestampRetrieved == 0) return 0;
      require(block.timestamp - _timestampRetrieved < 24 hours, "Data timestamp is more than 24 hours.");
      uint256 fetchPrice = abi.decode(_value, (uint256));

            // Bounds: 0.98 .. 1.02 
      uint256 lower = (ONE * (10_000 - TWO_PERCENT)) / 10_000; 
      uint256 upper = (ONE * (10_000 + TWO_PERCENT)) / 10_000; 

      require(fetchPrice >= lower && fetchPrice <= upper, "Dai peg off by >2%");

      return fetchPrice;
    }

    function getPdaiSpotPrice() public view returns(uint256) {
        uint256 plsPrice = getPlsSpotPrice();
        try IOracle(priceOracles[pdai]).consult(pdai, 1e18) returns (uint256 twapPrice) {
           return (twapPrice * plsPrice) / 1e18;
        } catch {
            revert("Failed to consult price from the oracle");
        }
    }

    function getfPDAISpotPrice() public view returns(uint256) {
       
        uint256 pdaiPrice = getPdaiSpotPrice();
        try IOracle(priceOracles[fpdai]).consult(fpdai, 1e18) returns (uint256 twapPrice) {
           return (twapPrice * pdaiPrice) / 1e18;
        } catch {
            revert("Failed to consult price from the oracle");
        }
    }

    function getfPLSSpotPrice() public view returns(uint256) {
       
        uint256 plsPrice = getPlsSpotPrice();
        try IOracle(priceOracles[fpls]).consult(fpls, 1e18) returns (uint256 twapPrice) {
           return (twapPrice * plsPrice) / 1e18;
        } catch {
            revert("Failed to consult price from the oracle");
        }
    }

    function getfPLSXSpotPrice() public view returns(uint256) {
       
        uint256 plsxPrice = getPlsxSpotPrice();
        try IOracle(priceOracles[fplsx]).consult(fplsx, 1e18) returns (uint256 twapPrice) {
           return (twapPrice * plsxPrice) / 1e18;
        } catch {
            revert("Failed to consult price from the oracle");
        }
    }

    function getTokenTWAP(address _token) public view returns (uint256) {
        
        try IOracle(priceOracles[_token]).consult(_token, 1e18) returns (uint256 twapPrice) {
            return twapPrice;
        } catch {
            revert("Failed to consult price from the oracle");
        }
    }

    function _absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? (a - b) : (b - a);
    }

    function _dexPrice(address[] memory path) internal view returns (uint256 dexPrice) {
        require(path.length >= 2, "Bad path");

        uint[] memory amts;
        try router.getAmountsOut(ONE, path) returns (uint[] memory r) {
            amts = r;
        } catch {
            revert("No DEX route/liquidity");
        }

        uint256 outRaw = amts[amts.length - 1];

        uint8 outDec = IERC20Metadata(path[path.length - 1]).decimals();
        if (outDec >= 18) {
            dexPrice = outRaw / (10 ** (outDec - 18));
        } else {
            dexPrice = outRaw * (10 ** (18 - outDec));
        }
    }

    function setPriceOracle(address token, address oracle) external onlyOwner {
        require(oracle != address(0), "Invalid oracle");
        priceOracles[token] = oracle;
    }

    function setMaxBps(uint256 _bps) external onlyOwner {
        require(_bps <= 1500, "Maxbps too high");
        maxBps = _bps;
    }

}