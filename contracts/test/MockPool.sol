// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

contract MockPool {

    address public receiverAddress;
    address public  asset;
    uint256 public  amount;
    uint256 public interestRateModes;
    bytes public params;
    uint16 public referralCode;
    constructor(){
    }


    function flashLoanSimple(
        address _receiverAddress,
        address _asset,
        uint256 _amount,
        bytes calldata _params,
        uint16 _referralCode
    ) external {

        receiverAddress = _receiverAddress;
        asset = _asset;
        amount = _amount;
        params = _params;
        referralCode = _referralCode;
    }
}
