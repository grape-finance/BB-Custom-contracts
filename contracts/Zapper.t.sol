import {LPZapper} from "./Zapper.sol";
import {Test} from "forge-std/Test.sol";

contract CounterTest is Test {
    LPZapper zapper;
    LPZapper zapper2;

    address public constant PDAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant PLSX = 0x95B303987A60C71504D99Aa1b13B4DA07b0790ab;
    address public constant PLS = 0xA1077a294dDE1B09bB078844df40758a5D0f9a27;
    address public constant FAVOR_PDAI =
        0xBc91E5aE4Ce07D0455834d52a9A4Df992e12FE12;
    address public constant FAVOR_PLSX =
        0x47c3038ad52E06B9B4aCa6D672FF9fF39b126806;
    address public constant FAVOR_PLS =
        0x30be72a397667FDfD641E3e5Bd68Db657711EB20;
    address public constant PLSFLP = 0xdca85EFDCe177b24DE8B17811cEC007FE5098586;
    address public constant PLSXFLP =
        0x24264d580711474526e8F2A8cCB184F6438BB95c;
    address public constant PDAIFLP =
        0xA0126Ac1364606BAfb150653c7Bc9f1af4283DFa;

    function setUp() public {
        zapper = new LPZapper(address(this), PLS, 0x165C3410fC91EF562C50559f7d2289fEbed552d9);
        zapper2 = new LPZapper(PDAI, PLS, 0x165C3410fC91EF562C50559f7d2289fEbed552d9);
    }

    function test_setUp() public {
        zapper.addDustToken(PDAI);
        zapper.addDustToken(PLSX);
        zapper.addDustToken(PLS);
        zapper.addDustToken(FAVOR_PDAI);
        zapper.addDustToken(FAVOR_PLSX);
        zapper.addDustToken(FAVOR_PLS);
        zapper.addFavorToToken(FAVOR_PDAI, PDAI);
        zapper.addFavorToToken(FAVOR_PLSX, PLSX);
        zapper.addFavorToToken(FAVOR_PLS, PLS);
        zapper.addFavorToLp(FAVOR_PDAI, PDAIFLP);
        zapper.addFavorToLp(FAVOR_PLSX, PLSXFLP);
        zapper.addFavorToLp(FAVOR_PLS, PLSFLP);
        zapper.addTokenToFavor(PDAI, FAVOR_PDAI);
        zapper.addTokenToFavor(PLSX, FAVOR_PLSX);
        zapper.addTokenToFavor(PLS, FAVOR_PLS);
    }

    function test_ownerFailure() public {
        vm.expectRevert();
        zapper2.addDustToken(PDAI);
         vm.expectRevert();
        zapper2.addDustToken(PLSX);
         vm.expectRevert();
        zapper2.addDustToken(PLS);
         vm.expectRevert();
        zapper2.addDustToken(FAVOR_PDAI);
         vm.expectRevert();
        zapper2.addDustToken(FAVOR_PLSX);
         vm.expectRevert();
        zapper2.addDustToken(FAVOR_PLS);
         vm.expectRevert();
        zapper2.addFavorToToken(FAVOR_PDAI, PDAI);
         vm.expectRevert();
        zapper2.addFavorToToken(FAVOR_PLSX, PLSX);
         vm.expectRevert();
        zapper2.addFavorToToken(FAVOR_PLS, PLS);
         vm.expectRevert();
        zapper2.addFavorToLp(FAVOR_PDAI, PDAIFLP);
         vm.expectRevert();
        zapper2.addFavorToLp(FAVOR_PLSX, PLSXFLP);
         vm.expectRevert();
        zapper2.addFavorToLp(FAVOR_PLS, PLSFLP);
         vm.expectRevert();
        zapper2.addTokenToFavor(PDAI, FAVOR_PDAI);
         vm.expectRevert();
        zapper2.addTokenToFavor(PLSX, FAVOR_PLSX);
         vm.expectRevert();
        zapper2.addTokenToFavor(PLS, FAVOR_PLS);
    }
}
