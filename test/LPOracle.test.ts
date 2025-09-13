import {expect} from "chai";
import {network} from "hardhat";
import {ZeroAddress} from "ethers";
import {createToken, createUSV2Factory, createUSV2Router} from "./utils/contractUtils.js";
import {fail} from "node:assert";

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
        lpOracleOnstance.transferOwnership(owner);

        let lpOracle = lpOracleOnstance.connect(owner);


        return {lpOracle, favor, base, favorBasePair, masterOracle, originTime};
    }

    describe('deployment', () => {
        // shall be able to depoy contract,  basic settings shall be set
        it('shall be able to deploy', async () => {

            const [deployer, owner] = await ethers.getSigners();
            let {lpOracle, masterOracle, base, favor, favorBasePair} = await deployContracts()
            // shall deploy
            expect(lpOracle).to.not.equal(null);

            //  owner shall be set
            expect(await lpOracle.owner()).to.equal(deployer.address);

            let kTimestamLast = await  lpOracle.kTimestampLast();
            //
            expect(await lpOracle.masterOracle()).to.be.equal(masterOracle);
            expect(await lpOracle.pair()).to.be.equal(favorBasePair);
            expect(await lpOracle.token0()).to.be.equal(await favorBasePair.token0());
            expect(await lpOracle.token1()).to.be.equal(await favorBasePair.token1());
            expect(await lpOracle.lpPriceCap()).to.be.equal(10000n);
            expect(await lpOracle.lastLpPrice()).to.be.equal(10000n);
            expect(await lpOracle.getPeriod()).to.be.equal(3600n);
            expect(await lpOracle.blockTimestampLast()).to.be.equal(kTimestamLast);


            expect(await lpOracle.kTimestampLast()).to.be.equal(0);
            expect(await lpOracle.kCumulativeLast()).to.be.equal(0);
            expect(await lpOracle.lastSqrtK()).to.be.equal(0);
            expect(await lpOracle.usdTimestampLast()).to.be.equal(0);


            //  those calculations  of expected shall use timestamps
            if (await lpOracle.token0() == await favor.getAddress()) {
                expect(await lpOracle.price0CumulativeLast()).to.be.equal(123);
                expect(await lpOracle.price1CumulativeLast()).to.be.equal(234);
                expect(await lpOracle.usd0CumulativeLast()).to.be.equal(234);
                expect(await lpOracle.usd1CumulativeLast()).to.be.equal(234);
            } else {
                expect(await lpOracle.price0CumulativeLast()).to.be.equal(234);
                expect(await lpOracle.price1CumulativeLast()).to.be.equal(123);
                expect(await lpOracle.usd0CumulativeLast()).to.be.equal(234);
                expect(await lpOracle.usd1CumulativeLast()).to.be.equal(234);
            }
        })
    })

    describe('access control', () => {
        it('only owner shall be able to call those methods', async () => {
            fail('implement me')
        })

        it('only alowed user shall be able to initiate epoch chaneg' , async () => {
            fail('implement me')
        })
    })

});
