// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";

// @dev  Inspired by "Killwitch engage"
contract Killswitch is Ownable2Step {

    mapping(address => bool) public scram;
    mapping(address => bool) public releaser;

    event Engaged(address who);
    event Released(address who, bool done);

    //  not engaged by default
    bool public engaged = false;
    uint8 public needReleases = 0;

    address[]  private  released;

    uint8 public immutable releaseThreshold;

    constructor(uint8 _releaseThreshold, address _owner) Ownable(_owner)
    {
        releaseThreshold = _releaseThreshold;
        released = new address[](releaseThreshold - 1);
    }

    //  give or revoke permission to scram.  scrammer can not be releaser!
    function setScram(address _who, bool _isHe) public onlyOwner {
        require(!releaser[_who], "Killswitch: releaser cannot be scramer");
        scram[_who] = _isHe;
    }

    // give or revoke permission to release,  can not be scrammer!
    function setReleaser(address _who, bool _isHe) public onlyOwner {
        require(!scram[_who], "Killswitch: releaser cannot be scramer");
        releaser[_who] = _isHe;
    }

    // SCRAM!
    function engage() public {
        require(scram[_msgSender()], "Killswitch: not scram");
        engaged = true;
        needReleases = releaseThreshold;

        emit Engaged(_msgSender());
    }


    function release() public {
        require(releaser[_msgSender()], "Killswitch: not releaser");

        //  was this user already active?
        for (uint8 i = 0; i < releaseThreshold - needReleases; i++) {
            require(released[i] != _msgSender(), "Killswitch: already released");
        }
        //  am I last necessary vote?
        if (needReleases == 1) {
            // release
            engaged = false;
            needReleases = 0;
        } else {
            // mark user as he already spent his vote
            released[releaseThreshold - needReleases] = _msgSender();
            needReleases--;
        }
        emit Released(_msgSender(), needReleases == 0);
    }

}
