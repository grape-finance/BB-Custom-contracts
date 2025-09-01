// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "./AbstractFavor.sol";

contract FavorPLS is AbstractFavor {

    string private constant NAME = "Favor PLS";
    string private constant SYMBOL = "fPLS";

    constructor(address _owner, uint256 _initialSupply, address _treasury, address _esteem)
    AbstractFavor(_owner, NAME, SYMBOL, _initialSupply, _treasury, _esteem){

    }

}