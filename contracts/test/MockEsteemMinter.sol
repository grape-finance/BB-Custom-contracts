// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// MOck Esteem minter to be used for test purposes
contract MockEsteemMinter {

    mapping(address => uint256) public tokenPrice;
    uint256 public esteemRate;
    constructor(){
    }

    //  18 decimals fixed price in ETH
    function setTokenPrice(address _favor, uint256 _price) public {
        tokenPrice[_favor] = _price;
    }



    // 18 decimals fixed point esteem price in USD
    function setEsteemRate(uint256 _esteemRate) public {
        esteemRate = _esteemRate;
    }

    //  18 decimals fixed price in ETH
    function getLatestTokenPrice(address _favor) public returns (uint256) {
        return tokenPrice[_favor];
    }


}
