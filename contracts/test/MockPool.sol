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
    function mockExecute(address _target, address _user, address _asset, uint256 _amount, uint256 _premium, address _favor, address _lp) external {
        bytes memory data = abi.encode(_user, _favor, _lp);

        IFlashLoanSimpleReceiver(_target).executeOperation(_asset, _amount, _premium, _target, data);
    }

    // simulate flash loan execution coming from a defined  initiator  address
    function mockLoanFromWrongInitiator(address _target, address _initiator) external {
        IFlashLoanSimpleReceiver(_target).executeOperation(_target, 123, 4546, _initiator, new bytes(0));
    }

    // simulate flash loan execution with wring user passed in data
    function mockLoanFromWrongUser(address _target, address _fakeUser) external {
        bytes memory data = abi.encode(_fakeUser, _target, _target);

        IFlashLoanSimpleReceiver(_target).executeOperation(_target, 123, 4546, _target, data);
    }

    // mock supply
    bool public supplyCalled;
    address public assetSupplied;
    uint256 public amountSupplied;
    address  public suppliedTo;
    uint256 public supplyReferral;

    function supply(address _lpToken, uint256 _lpAmountProvided, address _suppliedTo, uint16 _referral) external {
        supplyCalled = true;
        assetSupplied = _lpToken;
        amountSupplied = _lpAmountProvided;
        suppliedTo = _suppliedTo;
        supplyReferral = _referral;
    }

    // mock borrow
    bool public  borrowCalled;
    address  public assetBorrowed;
    uint256 public amountBorrowed;
    uint256 public interestRateMode;
    uint256 public  borrowReferral;
    address public  borrowedFrom;

    function borrow(address _asset, uint256 _borrowed, uint _interestRateMode, uint16 _referral, address _borrowsedFrom) external {

        borrowCalled = true;
        assetBorrowed = _asset;
        amountBorrowed = _borrowed;
        interestRateMode = _interestRateMode;
        borrowReferral = _referral;
        borrowedFrom = _borrowsedFrom;
    }
}
