// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;



import "./AbstractFavor2.sol";

contract FavorPLS2 is AbstractFavor2 {

    string private constant NAME = "Favor PLS";
    string private constant SYMBOL = "fPLS";

    constructor(address _owner, uint256 _initialSupply, address _treasury, address _esteem)
    AbstractFavor2(_owner, NAME, SYMBOL, _initialSupply, _treasury, _esteem){

    }

}