// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// MOck Esteem minter to be used for test purposes
contract MockEsteemMinter {

    mapping(address => uint256) public favorPrice;
    uint256 public ethPrice;
    uint256 public esteemRate;

    constructor(){
    }

    //  18 decimals fixed price in ETH
    function setFavorPrice(address _favor, uint256 _price) public {
        favorPrice[_favor] = _price;
    }

    //  18 decimals fixed price in USD
    function setEthPrice(uint256 _ethPrice) public {
        ethPrice = _ethPrice;
    }

    // 18 decimals fixed point esteem price in USD
    function setEsteemRate(uint256 _esteemRate) public {
        esteemRate = _esteemRate;
    }

    //  18 decimals fixed price in ETH
    function getFavorPrice(address _favor) public returns (uint256) {
        return favorPrice[_favor];
    }


    function latestETHPrice()  public returns (uint256) {
        return ethPrice;
    }
}
