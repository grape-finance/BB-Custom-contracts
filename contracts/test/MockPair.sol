// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;
contract MockPair {
    address public token0;
    address public token1;
    uint112 private reserve0;
    uint112 private reserve1;
    uint256 private _totalSupply;

    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
    }

    function setReserves(uint112 _reserve0, uint112 _reserve1) external {
        reserve0 = _reserve0;
        reserve1 = _reserve1;
    }

    function setTotalSupply(uint256 supply) external {
        _totalSupply = supply;
    }

    function getReserves() external view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, 0);
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }
}