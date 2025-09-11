// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./usingFetch/usingFetch.sol";
import "./interfaces/IOracle.sol";

contract MinterOracle is UsingFetch, Ownable {

    //fetch oracle feed testnet 0xe5284f722a509659ec70aa236BA08E10B263bCB2
    //fetch oracle feed mainnet 0xCe9DEa26eB6bEaEc73CFf3BACdF3F9e42BB89951

    address public constant wpls = 0xA1077a294dDE1B09bB078844df40758a5D0f9a27;
    address public constant plsx = 0x95B303987A60C71504D99Aa1b13B4DA07b0790ab;
    address public constant pdai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address public constant fpls = 0x30be72a397667FDfD641E3e5Bd68Db657711EB20;
    address public constant fplsx = 0x47c3038ad52E06B9B4aCa6D672FF9fF39b126806;
    address public constant fpdai = 0xBc91E5aE4Ce07D0455834d52a9A4Df992e12FE12;

    address public constant fplsLP = 0xdca85EFDCe177b24DE8B17811cEC007FE5098586;
    address public constant fplsxLP = 0x24264d580711474526e8F2A8cCB184F6438BB95c;
    address public constant fpdaiLP = 0xA0126Ac1364606BAfb150653c7Bc9f1af4283DFa;


    mapping(address => address) public priceOracles;

    constructor(address payable _fetchAddress, address _owner) UsingFetch(_fetchAddress) Ownable(_owner) 
    {}

    function getLatestPrice(address _token) public view returns(uint256) {

        if(_token == address(0) || _token == wpls){
            return getPlsSpotPrice();
        }else if(_token == plsx){
            return getPlsxSpotPrice();
        }else if(_token == pdai){
            return getPdaiSpotPrice();
        }else if(_token == fpls){
            return getfPLSSpotPrice();
        }else if(_token == fplsx){
            return getfPLSXSpotPrice();
        }else if(_token == fpdai){
            return getfPDAISpotPrice();
        }else if(_token == fplsLP){
            return getTokenTWAP(fplsLP);
        }else if(_token == fplsxLP){
            return getTokenTWAP(fplsxLP);
        }else if(_token == fpdaiLP){
            return getTokenTWAP(fpdaiLP);
        }
    
     return 0;      
        
    }
    
    function getPlsSpotPrice() public view returns(uint256) {
    
      bytes memory _queryData = abi.encode("SpotPrice", abi.encode("pls", "usd"));
      bytes32 _queryId = keccak256(_queryData);
      
      (bytes memory _value, uint256 _timestampRetrieved) =
          getDataBefore(_queryId, block.timestamp - 20 minutes);
      if (_timestampRetrieved == 0) return 0;
      require(block.timestamp - _timestampRetrieved < 24 hours, "Data timestamp is more than 24 hours.");
      return abi.decode(_value, (uint256));
    }

    function getPlsxSpotPrice() public view returns(uint256) {
    
      bytes memory _queryData = abi.encode("SpotPrice", abi.encode("plsx", "usd"));
      bytes32 _queryId = keccak256(_queryData);
      
      (bytes memory _value, uint256 _timestampRetrieved) =
          getDataBefore(_queryId, block.timestamp - 20 minutes);
      if (_timestampRetrieved == 0) return 0;
      require(block.timestamp - _timestampRetrieved < 24 hours, "Data timestamp is more than 24 hours.");
      return abi.decode(_value, (uint256));
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

    function setPriceOracle(address token, address oracle) external onlyOwner {
        require(oracle != address(0), "Invalid oracle");
        priceOracles[token] = oracle;
    }

}