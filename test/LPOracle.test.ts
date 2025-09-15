import {expect} from "chai";
import {network} from "hardhat";
import {createToken, createUSV2Factory, createUSV2Router} from "./utils/contractUtils.js";

const {ethers} = await network.connect();

describe('LPOracle.sol', () => {

    async function deployContracts() {

        const [deployer, owner] = await ethers.getSigners();

        //  tokens
        let favor = await createToken(owner, 'favor', "f0");
        let base = await createToken(owner, 'nase', "b0");

        let v2factory = await createUSV2Factory(owner);
        let v2router = await createUSV2Router(owner, v2factory, base);

        //  pair
        // and another liqiodity pool
        await favor.approve(v2router, 1_000_000_000_000_000_000n);
        await base.approve(v2router, 1_000_000_000_000_000_000n);

        await v2factory.createPair(favor, base);
        let pairAdr = await v2factory.getPair(favor, base);

        let favorBasePair = await ethers.getContractAt("IUniswapV2Pair", pairAdr, owner);


        await v2router.addLiquidity(favor, base, 1000000n, 2000000n, 0n, 0n, owner, Date.now() + 100000)


        let masterOracleInstance = await ethers.deployContract("MockMasterOracle", []);
        let masterOracle = masterOracleInstance.connect(owner);


        await masterOracle.setLastPrice(favor, 123n);
        await masterOracle.setLastPrice(base, 234n);


        let originTime = Date.now();
        const lpOracleOnstance = await ethers.deployContract("LPOracle", [favorBasePair, masterOracle, 3600, originTime, 10000n]);
        const deployTimestamp = (await ethers.provider.getBlock("latest")).timestamp;

        await lpOracleOnstance.transferOwnership(owner);

        let lpOracle = lpOracleOnstance.connect(owner);


        return {lpOracle, favor, base, favorBasePair, masterOracle, originTime, deployTimestamp};
    }

    describe('deployment', () => {
        // shall be able to depoy contract,  basic settings shall be set
        it('shall be able to deploy', async () => {

            const [deployer, owner] = await ethers.getSigners();
            let {lpOracle, masterOracle, base, favor, favorBasePair, deployTimestamp} = await deployContracts()
            // shall deploy
            expect(lpOracle).to.not.equal(null);

            //  owner shall be set
            expect(await lpOracle.owner()).to.equal(owner.address);

            let kTimestamLast = await lpOracle.kTimestampLast();
            //
            expect(await lpOracle.masterOracle()).to.be.equal(masterOracle);
            expect(await lpOracle.pair()).to.be.equal(favorBasePair);
            expect(await lpOracle.token0()).to.be.equal(await favorBasePair.token0());
            expect(await lpOracle.token1()).to.be.equal(await favorBasePair.token1());
            expect(await lpOracle.lpPriceCap()).to.be.equal(10000n);
            expect(await lpOracle.getPeriod()).to.be.equal(3600n);
            expect(await lpOracle.blockTimestampLast()).to.be.equal(kTimestamLast);


            expect(await lpOracle.kTimestampLast()).to.be.equal(deployTimestamp);
            // TODO:  disable tests are time dependentm and need to be fixed
            //   expect(await lpOracle.kCumulativeLast()).to.be.equal(9127198453520499144822365807547012586930176n);
            expect(await lpOracle.lastSqrtK()).to.be.equal(5192296858534827628530496329220096n);
            //   expect(await lpOracle.usdTimestampLast()).to.be.equal(0);

            //TODO:  cumulativ eproces are time dependent  - needto be fikxed

            //  those calculations  of expected shall use timestamps
            if (await lpOracle.token0() == await favor.getAddress()) {
                //        expect(await lpOracle.price0CumulativeLast()).to.be.equal(123);
                //        expect(await lpOracle.price1CumulativeLast()).to.be.equal(234);
                //        expect(await lpOracle.usd0CumulativeLast()).to.be.equal(234);
                //       expect(await lpOracle.usd1CumulativeLast()).to.be.equal(234);
            } else {
                //        expect(await lpOracle.price0CumulativeLast()).to.be.equal(234);
                //        expect(await lpOracle.price1CumulativeLast()).to.be.equal(123);
                //        expect(await lpOracle.usd0CumulativeLast()).to.be.equal(234);
                //        expect(await lpOracle.usd1CumulativeLast()).to.be.equal(234);
            }
        })
    })

    describe('access control', () => {
        it('only owner shall be able to do this', async () => {

            const [deployer, owner, somebody] = await ethers.getSigners();
            let {lpOracle} = await deployContracts()

            await expect(lpOracle.connect(somebody).setApprovedUser(somebody, true)).to.be.revertedWithCustomError(lpOracle, "OwnableUnauthorizedAccount");
            await expect(lpOracle.connect(somebody).setMasterOracle(somebody)).to.be.revertedWithCustomError(lpOracle, "OwnableUnauthorizedAccount");
            await expect(lpOracle.connect(somebody).setPeriod(123)).to.be.revertedWithCustomError(lpOracle, "OwnableUnauthorizedAccount");
            await expect(lpOracle.connect(somebody).setEpoch(123)).to.be.revertedWithCustomError(lpOracle, "OwnableUnauthorizedAccount");

        })

        it('only approved shall be able to this', async () => {

            const [deployer, owner, somebody] = await ethers.getSigners();
            let {lpOracle} = await deployContracts()

            await expect(lpOracle.connect(somebody).update()).to.be.revertedWith("Epoch: caller not approved");

        })
    })

    describe('change settings', () => {
        it('shall update approval seting', async () => {

            const [deployer, owner, somebody] = await ethers.getSigners();
            let {lpOracle} = await deployContracts();

            expect(await lpOracle.isApprovedUser(somebody)).to.equal(false);

            await expect(lpOracle.setApprovedUser(somebody, true)).to.emit(lpOracle, "ApprovedUserSet").withArgs(somebody, true);

            expect(await lpOracle.isApprovedUser(somebody)).to.equal(true);

        })


        it('approved user shall trigger update', async () => {

            const [deployer, owner, somebody] = await ethers.getSigners();
            let {lpOracle} = await deployContracts();

            await lpOracle.setApprovedUser(somebody, true);

            await expect(lpOracle.connect(somebody).update()).to.emit(lpOracle, "Updated");

        })
    })

    describe('possible issues', () => {

        //  Zokyo expresses concern: what happens in case staker is not set to be tax-exempt
        //  this could prevent proper aallocation of favor to it
        it('shall behave properly in case  tax exemt misconfiguration', async () => {

        })
    })
});
