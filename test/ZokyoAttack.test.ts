import {network, tasks} from "hardhat";
import {createToken, createUSV2Factory, createUSV2Router} from "./utils/contractUtils.js";
import {expect} from "chai";

const {ethers, networkHelpers} = await network.connect();


describe('ZokyoAttack', () => {

    async function deployContracts() {
        const [owner, treasury, alice] = await ethers.getSigners();

        //  as we do not have fetsh orcle here, use mock
        let mockOracle = await ethers.deployContract("MockMasterOracle");


        let startTime = Math.floor(Date.now() / 1000);

        const esteem = await ethers.deployContract("Esteem", [owner]);
        await esteem.addMinter(owner);
        await esteem.mint(owner, 1000n);


        const minter = await ethers.deployContract("MintRedeemer", [esteem, startTime + 100, owner]);
        // 0.1 ,  18 digitts fixed decimal point
        await minter.setEsteemRate(100_000_000_000_000_000n)


        let weth = await createToken(owner, 'wethweth', "t0");
        await minter.setPriceOracle(weth, mockOracle);
        await mockOracle.setLastPrice(weth, 1_000_000_000_000_000_000n);

        let v2factory = await createUSV2Factory(owner);
        let v2router = await createUSV2Router(owner, v2factory, weth);


        const zapper = await ethers.deployContract("LPZapper", [owner, v2router]);

        // mock pool to test flash loans
        const mockPool = await ethers.deployContract("MockPool", []);


        await zapper.setPool(mockPool);


        const favorEth = await ethers.deployContract("Favor", [owner, "FavorPLS", "fPLS", 1_000_000_000_000_000_000_000_000_000_000_000n, treasury, esteem]);
        await favorEth.setPriceProvider(minter);
        await esteem.addMinter(favorEth);

        await minter.setPriceOracle(favorEth, mockOracle);


        // 1$
        await mockOracle.setLastPrice(favorEth, 1_000_000_000_000_000_000n);
        //  alice is a rich girl
        await favorEth.transfer(alice, 1_000_000_000_000n);
        await weth.transfer(alice, 1_000_000_000_000n);

        await favorEth.setTaxExempt(zapper, true);
        // to be able to create LPs for test pusposes
        await favorEth.setTaxExempt(owner, true);
        await favorEth.setBuyWrapper(zapper, true);


        //  create weth / favor liquidity pool
        await favorEth.approve(v2router, 1_000_000_000_000_000_000_000_000_000n);
        await weth.approve(v2router, 1_000_000_000_000_000_000_000_000_000n);


        // pair
        await v2factory.createPair(favorEth, weth);
        let pairAdr = await v2factory.getPair(favorEth, weth);

        let favorWethPair = await ethers.getContractAt("IUniswapV2Pair", pairAdr, owner);
        await v2router.addLiquidity(favorEth, weth, 10_000_000_000_000n, 10_000_000_000_000n, 0n, 0n, owner, Date.now() + 100000)


        // register this pair as favor pair
        await zapper.addFavor(favorEth, favorWethPair, weth);

        // remove tax-exempt status from owner
        await favorEth.setTaxExempt(owner, false);


        let genesis = (await ethers.provider.getBlock('latest'))?.timestamp || 0;
        const epochKeeper = await ethers.deployContract("EpochKeeper", [genesis, 3600, owner]);

        const uniTwapOracle = await ethers.deployContract("UniTWAPOracle", [favorWethPair, 1000_000_000_000_000_000_000n, epochKeeper, owner]);
        await mockOracle.setTwapOracle(favorEth, uniTwapOracle);

        //  create grove
        let grove = await ethers.deployContract("Staking", [epochKeeper, owner]);
        // groove shall be tax exempt
        await favorEth.setTaxExempt(grove, true);

        //  create and inialise favor treasury,
        const favorTreasury = await ethers.deployContract("FavorTreasury", [epochKeeper, owner]);
        await favorEth.setTaxExempt(favorTreasury, true);

        await favorTreasury.initialize(favorEth, uniTwapOracle, grove);


        //  initialise staking and stack some favor
        await grove.initialize(favorEth, esteem, favorTreasury);
        // and ensure that something is stacked
        await esteem.approve(grove, 1000n);
        await grove.stake(1000n);

        //  favor treasury is allowed to consult and update oracle
        await uniTwapOracle.setApprovedUser(favorTreasury, true);

        //  favor treasury shall be a minter for favor
        await favorEth.addMinter(favorTreasury);

        //  treasury is aithorised to allocate seigniorage
        await grove.setTreasuryOperator(favorTreasury);


        // create and configure mint redeemer
        let timestampNow = (await ethers.provider.getBlock('latest'))?.timestamp || 0;
        const mintRedeemer = await ethers.deployContract("MintRedeemer", [esteem, timestampNow + 10, owner]);
        await mintRedeemer.setActiveFavorToken(favorEth, true);
        await mintRedeemer.setPriceOracle(favorEth, mockOracle);

        //  mint redeemer is allowed to mint esteem
        await favorEth.addMinter(mintRedeemer);

        // seignoreage allocated
        await favorTreasury.allocateSeigniorage();

        //  advance to the next epoch
        await networkHelpers.time.increaseTo(await epochKeeper.currentEpochEndTime() + 10n);
        //  oracle is updated
        await expect(uniTwapOracle.update()).to.not.be.revert(ethers);

        console.log("consult:", await uniTwapOracle.consult(favorEth, 1000n));

        return {
            zapper,
            favorEth,
            weth,
            favorWethPair,
            v2router,
            esteem,
            favorTreasury,
            uniTwapOracle,
            mockPool,
            grove,
            mockOracle,
            epochKeeper,
            mintRedeemer,
        };
    }


    describe('various attacks', () => {

        it('attempt to attack by alice', async () => {
            const [owner, treasury, alice, bob] = await ethers.getSigners();
            let {
                zapper,
                weth,
                favorWethPair,
                favorEth,
                favorTreasury,
                uniTwapOracle,
                esteem,
                mintRedeemer,
            } = await networkHelpers.loadFixture(deployContracts);


            //  alice has a lot of WETH, 10% of pool value
            console.log("alice has weth:", await weth.balanceOf(alice));
            let initialFavorBalance = await favorEth.balanceOf(alice);
            console.log("alice has favor:", initialFavorBalance);

            let initalWethBalance = await weth.balanceOf(alice);
            //  alice buys favor, 10% of pool value
            await weth.connect(alice).approve(zapper, 1_000_000_000_000n);
            console.log('allowance:', await weth.allowance(alice, zapper));
            await expect(zapper.connect(alice).buy(weth, 1_000_000_000_000n, 0n, Date.now())).to.not.be.revert(ethers);

            console.log("alice bought favor:", await favorEth.balanceOf(alice));

            // alice claims bouns and receives favor
            await expect(favorEth.connect(alice).claimBonus()).to.not.be.revert(ethers);
            let aliceBalabceOfEsteem = await esteem.balanceOf(alice);
            console.log("alice claimed bonus and received esteem:", aliceBalabceOfEsteem);

            // alice is smelting favor
            await esteem.connect(alice).approve(mintRedeemer, aliceBalabceOfEsteem);
            await expect(mintRedeemer.connect(alice).redeemFavor(aliceBalabceOfEsteem, favorEth)).to.not.be.revert(ethers);

            let balancAfterSmelting = await favorEth.balanceOf(alice) - initialFavorBalance;
            console.log("alice has favor after smelting:", balancAfterSmelting);

            //  alice is selling this favor for ETH
            await favorEth.connect(alice).approve(zapper, balancAfterSmelting);
            await expect(zapper.connect(alice).sell(favorEth, balancAfterSmelting, 0, Date.now())).to.not.be.revert(ethers);

            let wethBalanceAfterAttack = await weth.balanceOf(alice);

            console.log("balace after attack:", wethBalanceAfterAttack);
            console.log("attacj earns:", wethBalanceAfterAttack - initalWethBalance);
        })
    });
})