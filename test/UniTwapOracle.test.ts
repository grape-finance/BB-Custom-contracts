import {expect} from "chai";
import {network} from "hardhat";
import {createToken, createUSV2Factory, createUSV2Router} from "./utils/contractUtils.js";

const {ethers, networkHelpers} = await network.connect();

describe('UniTWAPOracle.sol', () => {

    async function deployContracts() {

        const [owner] = await ethers.getSigners();

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


        let genesis = (await ethers.provider.getBlock('latest'))?.timestamp || 0;
        const epochKeeper = await ethers.deployContract("EpochKeeper", [genesis, 3600, owner]);

        let originTime = Date.now();
        const uniTWAPOracle = await ethers.deployContract("UniTWAPOracle", [favorBasePair, 10000n, epochKeeper, owner]);

        const deployTimestamp = (await ethers.provider.getBlock("latest"))?.timestamp || 0;


        return {uniTWAPOracle, favor, base, favorBasePair, masterOracle, originTime, deployTimestamp, epochKeeper};
    }

    describe('deployment', () => {
        // shall be able to depoy contract,  basic settings shall be set
        it('shall be able to deploy', async () => {

            const [owner] = await ethers.getSigners();
            let {
                uniTWAPOracle,
                masterOracle,
                base,
                favor,
                favorBasePair,
                deployTimestamp
            } = await networkHelpers.loadFixture(deployContracts);
            // shall deploy
            expect(uniTWAPOracle).to.not.equal(null);

            //  owner shall be set
            expect(await uniTWAPOracle.owner()).to.equal(owner.address);


            //
            expect(await uniTWAPOracle.pair()).to.be.equal(favorBasePair);
            expect(await uniTWAPOracle.token0()).to.be.equal(await favorBasePair.token0());
            expect(await uniTWAPOracle.token1()).to.be.equal(await favorBasePair.token1());
            expect(await uniTWAPOracle.maxPriceCap()).to.be.equal(10000n);
            expect(await uniTWAPOracle.getPeriod()).to.be.equal(3600n);

            let [, , blockTImestamLast] = await favorBasePair.getReserves();
            expect(await uniTWAPOracle.blockTimestampLast()).to.be.equal(blockTImestamLast);

        })
    })

    describe('access control', () => {
        it('only owner shall be able to do this', async () => {

            const [owner, somebody] = await ethers.getSigners();
            let {
                uniTWAPOracle
            } = await networkHelpers.loadFixture(deployContracts);


            await expect(uniTWAPOracle.connect(somebody).setApprovedUser(somebody, true)).to.be.revertedWithCustomError(lpOracle, "OwnableUnauthorizedAccount");

        })

        it('only approved shall be able to this', async () => {

            const [deployer, owner, somebody] = await ethers.getSigners();
            let {uniTWAPOracle} = await networkHelpers.loadFixture(deployContracts);

            await expect(uniTWAPOracle.connect(somebody).update()).to.be.revertedWith("Epoch: caller not approved");

        })
    })

    describe('change settings', () => {
        it('shall update approval seting', async () => {

            const [deployer, owner, somebody] = await ethers.getSigners();
            let {uniTWAPOracle} = await deployContracts();

            expect(await uniTWAPOracle.isApprovedUser(somebody)).to.equal(false);

            await expect(uniTWAPOracle.setApprovedUser(somebody, true)).to.emit(lpOracle, "ApprovedUserSet").withArgs(somebody, true);

            expect(await uniTWAPOracle.isApprovedUser(somebody)).to.equal(true);

        })


        it('even approved user shall not trigger update before epoch is changed', async () => {

            const [owner, somebody] = await ethers.getSigners();
            let {uniTWAPOracle} = await deployContracts();

            await uniTWAPOracle.setApprovedUser(somebody, true);
            await expect(uniTWAPOracle.connect(somebody).update()).to.not.emit(lpOracle, "Updated");
        })
    })


    describe('updating', () => {

        it('shall update epoch when time comes', async () => {
            const [owner, somebody] = await ethers.getSigners();
            let {uniTWAPOracle, epochKeeper} = await networkHelpers.loadFixture(deployContracts);

            let [current, from, to] = await epochKeeper.currentEpochBoundary();

            await networkHelpers.time.increaseTo(to + 1n);
            await expect(uniTWAPOracle.update()).to.emit(lpOracle, "Updated");

            expect(await uniTWAPOracle.currentEpoch()).to.be.equal(current + 1n);
        })

    })

});
