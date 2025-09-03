// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@aave/core-v3/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";

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

    // simulate flash loan execution coming from a defined  initiator  address
    function mockLoanFromWrongInitiator(address _target, address _initiator) external {
        IFlashLoanSimpleReceiver(_target).executeOperation(_target, 123, 4546, _initiator, new bytes(0));
    }
}
