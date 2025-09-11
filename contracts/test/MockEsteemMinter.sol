// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// MOck Esteem minter to be used for test purposes
contract MockEsteemMinter {

    mapping(address => uint256) public tokenPrice;
    mapping(address => uint256) public tokenTWAP;
    uint256 public esteemRate;
    constructor(){
    }

    //  18 decimals fixed price in ETH
    function setTokenPrice(address _favor, uint256 _price) public {
        tokenPrice[_favor] = _price;
    }

    function setTokenTWAP(address _favor, uint256 _twap) public {
        tokenTWAP[_favor] = _twap;
    }


    // 18 decimals fixed point esteem price in USD
    function setEsteemRate(uint256 _esteemRate) public {
        esteemRate = _esteemRate;
    }

    //  18 decimals fixed price in ETH
    function getLatestTokenPrice(address _favor) public view returns (uint256) {
        return tokenPrice[_favor];
    }

    function getLatestTokenTWAP(address _favor) public view returns (uint256) {
        return tokenTWAP[_favor];
    }
}
