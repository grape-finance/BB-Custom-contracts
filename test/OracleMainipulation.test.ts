import {network, tasks} from "hardhat";
import {createToken, createUSV2Factory, createUSV2Router} from "./utils/contractUtils.js";
import {expect} from "chai";

const {ethers, networkHelpers} = await network.connect();

describe('OracleManipulator', () => {


    async function deployContracts() {
        const [owner, treasury, alice, bob] = await ethers.getSigners();

        //  as we do not have fetsh orcle here, use mock
        let mockOracle = await ethers.deployContract("MockMasterOracle");


        let startTime = Math.floor(Date.now() / 1000);

        const esteem = await ethers.deployContract("Esteem", [owner]);
        await esteem.addMinter(owner);
        await esteem.mint(owner, 1_000_000_000_000_000_000_000_000n);


        const minter = await ethers.deployContract("MintRedeemer", [esteem, startTime + 100, owner]);
        // 0.1 ,  18 digitts fixed decimal point
        //await minter.setEsteemRate(100_000_000_000_000_000n)


        let weth = await createToken(owner, 'wethweth', "t0");
        await minter.setPriceOracle(weth, mockOracle);
        await mockOracle.setLastPrice(weth, 1_000_000_000_000_000_000n);

        let v2factory = await createUSV2Factory(owner);
        let v2router = await createUSV2Router(owner, v2factory, weth);


        const zapperInstance = await ethers.deployContract("LPZapper", [owner, v2router]);
        let zapper = zapperInstance.connect(owner);

        // mock pool to test flash loans
        const mockPoolInstance = await ethers.deployContract("MockPool", []);
        let mockPool = mockPoolInstance.connect(owner);


        await zapper.setPool(mockPool);


        const favorEth = await ethers.deployContract("Favor", [owner, "FavorPLS", "fPLS", 123_000_000_000_000_000_000_000_000n, treasury, esteem]);
        await favorEth.setPriceProvider(minter);
        await esteem.addMinter(favorEth);

        await minter.setPriceOracle(favorEth, mockOracle);


        //  alice is a rich girl
        await favorEth.transfer(alice, 1_000_000_000_000n);
        await weth.transfer(alice, 1_000_000_000_000n);

        await favorEth.setTaxExempt(zapper, true);
        // to be able to create LPs for test pusposes
        await favorEth.setTaxExempt(owner, true);
        await favorEth.setBuyWrapper(zapper, true);


        //  create weth / favor  liquidity pool
        await favorEth.approve(v2router, 1_000_000_000_000_000_000n);
        await weth.approve(v2router, 1_000_000_000_000_000_000n);


        // pair
        await v2factory.createPair(favorEth, weth);
        let pairAdr = await v2factory.getPair(favorEth, weth);

        let favorWethPair = await ethers.getContractAt("IUniswapV2Pair", pairAdr, owner);
        await v2router.addLiquidity(favorEth, weth, 2000000n, 2000000n, 0n, 0n, owner, Date.now() + 100000)


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
        await esteem.approve(grove, 1_000_000_000_000_000_000_000n);
        await grove.stake(1_000_000_000_000_000_000_000n);

        //  favor treasury is allowed to consult and update  oracle
        await uniTwapOracle.setApprovedUser(favorTreasury, true);

        //  favor treasury shall be a minter for favor
        await favorEth.addMinter(favorTreasury);

        //  treasury is aithorised to allocate seigniorage
        await grove.setTreasuryOperator(favorTreasury);


        //  oracle is updated
        await expect(uniTwapOracle.update()).to.not.be.revert(ethers);
        // seignoreage allocated
        await favorTreasury.allocateSeigniorage();

        //  advance to the next epoch
        await networkHelpers.time.increaseTo(await epochKeeper.currentEpochEndTime() + 10n);

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
        };
    }

    describe('manipulation  testing', () => {


        it('shall be able to resist manipulation', async () => {
            const [owner, tresury, alice, bob] = await ethers.getSigners();
            let {
                zapper,
                weth,
                favorWethPair,
                favorEth,
                favorTreasury,
                uniTwapOracle,
            } = await networkHelpers.loadFixture(deployContracts);

            await owner.sendTransaction({
                to: weth,
                value: 100_000_000_000n,
                });
            let favorPriceBefore = await favorTreasury.getFavorPrice();
            console.log("favorPriceBefore:", favorPriceBefore.toString());


            await expect(uniTwapOracle.update()).to.not.be.revert(ethers);

            let nextEpochPoint = await favorTreasury.nextEpochPoint();
            console.log(nextEpochPoint);

            expect(await uniTwapOracle.getCurrentEpoch()).to.be.equal(1);

            console.log("favor:", await favorEth.getAddress());
            console.log("weth:", await weth.getAddress());
            let t0Adr = await favorWethPair.token0();
            let t1Adr = await favorWethPair.token1();

            console.log("t0:", t0Adr, "t1:", t1Adr);

            let price0 = await uniTwapOracle.price0Average();
            let price1 = await uniTwapOracle.price1Average();

            console.log("price0", price0.toString());
            console.log("price1", price1.toString());


            await favorEth.connect(alice).approve(zapper, 10_000_000_000n);
            //  now go 1 minute before the current epoch
            networkHelpers.time.increaseTo(nextEpochPoint - 60n);

            //  alice sells a lot of favor, say 10m
            console.log("alice has favor:", await favorEth.balanceOf(alice));
            await expect(zapper.connect(alice).sell(favorEth, 10_000_000n, 0n, Date.now())).to.not.be.revert(ethers);

            //  and this should not have an effect on the price
            let price0After = await uniTwapOracle.price0Average();
            let price1After = await uniTwapOracle.price1Average();

            console.log("price0After", price0After.toString());
            console.log("price1After", price1After.toString());

            expect(price0After).to.be.equal(price0);
            expect(price1After).to.be.equal(price1);

            await networkHelpers.time.increaseTo(nextEpochPoint + 10n);
            //  next epoch
            await favorTreasury.allocateSeigniorage();

            let favorPriceAfter = await favorTreasury.getFavorPrice();

            console.log("favorPriceAfter:", favorPriceAfter.toString());
        })

    })


    it('test dumping a shitoad of WETH', async () => {
        const [owner, tresury, alice, bob] = await ethers.getSigners();
        let {
            zapper,
            weth,
            favorWethPair,
            favorEth,
            favorTreasury,
            uniTwapOracle,
            mockOracle,
            esteem
        } = await networkHelpers.loadFixture(deployContracts);


        let favorPriceBefore = await favorTreasury.getFavorPrice();
        console.log("favorPriceBefore:", favorPriceBefore.toString());


        await expect(uniTwapOracle.update()).to.not.be.revert(ethers);

        let nextEpochPoint = await favorTreasury.nextEpochPoint();
        console.log(nextEpochPoint);

        expect(await uniTwapOracle.getCurrentEpoch()).to.be.equal(1);

        console.log("favor:", await favorEth.getAddress());
        console.log("weth:", await weth.getAddress());
        let t0Adr = await favorWethPair.token0();
        let t1Adr = await favorWethPair.token1();

        console.log("t0:", t0Adr, "t1:", t1Adr);

        let price0 = await uniTwapOracle.price0Average();
        let price1 = await uniTwapOracle.price1Average();

        console.log("price0", price0.toString());
        console.log("price1", price1.toString());


        let pendingBonusStart = await favorEth.pendingBonus(alice);
        console.log("alice pending bonus:", pendingBonusStart.toString());

        await weth.connect(alice).approve(zapper, 10_000_000_000n);
        //  now go 1 minute before the current epoch
        networkHelpers.time.increaseTo(nextEpochPoint - 60n);

        // before bying, simulate favor price logic
        // as our pool is balanced,  favor proce is equal to  weth
        await mockOracle.setLastPrice(favorEth, 1_000_000_000_000_000_000n);


        //  alice bys a lot of favor, by dumping a shitload of weth
        console.log("alice has weth:", await weth.balanceOf(alice));
        await zapper.connect(alice).buy(weth, 10_000_000n, 0n, Date.now());

        console.log('---------  alice sold  a lot WETH -----------')

        let pendingBonusAfterSale = await favorEth.pendingBonus(alice);
        console.log("alice pending bonus:", pendingBonusAfterSale.toString());
        console.log("alice has havor:", await favorEth.balanceOf(alice));


        let [r0, r1] = await favorWethPair.getReserves();
        console.log("r0:", r0.toString(), "r1:", r1.toString());
        // now we have to adjust mock proce orcale!!!!
        console.log("consult favor: ", await uniTwapOracle.consult(favorEth, 1_000_000_000_000_000_000n));

        //  and this should not have an effect on the price
        let price0After = await uniTwapOracle.price0Average();
        let price1After = await uniTwapOracle.price1Average();

        console.log("price0After", price0After.toString());
        console.log("price1After", price1After.toString());

        expect(price0After).to.be.equal(price0);
        expect(price1After).to.be.equal(price1);

        //  advance to the next epoch
        await networkHelpers.time.increaseTo(nextEpochPoint + 10n);
        console.log('-----------epoch -----------')
        await favorTreasury.allocateSeigniorage();
        let favorTwapAfter = await uniTwapOracle.consult(favorEth, 1_000_000_000_000_000_000n);
        console.log("favor TWAP: ", favorTwapAfter);

        let snapshotFavorPrice = 0n;
        if (t0Adr.toLowerCase() == (await favorEth.getAddress()).toLowerCase()) {
            snapshotFavorPrice = 1_000_000_000_000_000_000n * r1 / r0;
        } else {
            snapshotFavorPrice = 1_000_000_000_000_000_000n * r0 / r1;
        }
        console.log("favor snapshot: ", snapshotFavorPrice);

        //  simulate favor price logic
        let newFavorPrice = 1_000_000_000_000_000_000n / favorTwapAfter * 1_000_000_000_000_000_000n;
        await mockOracle.setLastPrice(favorEth, newFavorPrice);

        let favorPriceAfter = await favorTreasury.getFavorPrice();

        console.log("favorPriceAfter:", favorPriceAfter.toString());


        console.log('----------- alice has claimed bonus -----------')
        await favorEth.connect(alice).claimBonus();
        console.log('alice has got esteem:', await esteem.balanceOf(alice));


    })


    it('shows Alice earning normally and Mallory draining with a TWAP attack', async () => {
        const [owner, treasury, alice, mallory] = await ethers.getSigners();
        const {
            zapper,
            weth,
            favorEth,
            favorWethPair,
            favorTreasury,
            mockOracle,
            esteem,
            grove,
        } = await networkHelpers.loadFixture(deployContracts);

        await grove.connect(owner).withdraw(1000n);
        console.log("Bootstrap stake removed so only real actors remain");

        const attackBankroll = 1_000_000_000_000n;
        await weth.connect(owner).transfer(mallory.address, attackBankroll);
        console.log("Owner seeds Mallory with", attackBankroll.toString(), "WETH for the upcoming attack");

        console.log("\n=== Baseline epoch: honest user Alice ===");
        const aliceStake = 1_000_000_000_000_000_000n;
        await esteem.connect(owner).mint(alice.address, aliceStake);
        await esteem.connect(alice).approve(grove, aliceStake);
        await grove.connect(alice).stake(aliceStake);
        console.log("Alice stakes", aliceStake.toString(), "ESTEEM to earn baseline rewards");

        const firstEpochPoint = BigInt(await favorTreasury.nextEpochPoint());
        const baselineBlock = await ethers.provider.getBlock('latest');
        const currentTsBaseline = BigInt(baselineBlock?.timestamp ?? 0);
        let baselineTarget = firstEpochPoint + 5n;
        if (baselineTarget <= currentTsBaseline) {
            baselineTarget = currentTsBaseline + 5n;
        }
        await networkHelpers.time.increaseTo(baselineTarget);
        await favorTreasury.allocateSeigniorage();

        const baselinePrice = await favorTreasury.getFavorPrice();
        const aliceBaselineReward = await grove.earned(alice.address);
        console.log("Treasury TWAP after honest epoch:", baselinePrice.toString());
        console.log("Alice earns honest seigniorage:", aliceBaselineReward.toString());
        await grove.connect(alice).claimReward();
        console.log("Alice claims baseline reward, balance now:", (await favorEth.balanceOf(alice.address)).toString());

        console.log("\n=== Manipulated epoch: Mallory attacks ===");
        const malloryStake = 1_000_000_000_000_000_000n;
        await esteem.connect(owner).mint(mallory.address, malloryStake);
        await esteem.connect(mallory).approve(grove, malloryStake);
        await grove.connect(mallory).stake(malloryStake);
        console.log("Mallory stakes", malloryStake.toString(), "ESTEEM moments before the next epoch");

        const secondEpochPoint = BigInt(await favorTreasury.nextEpochPoint());

        await mockOracle.setLastPrice(favorEth, 1_000_000_000_000_000_000n);
        await weth.connect(mallory).approve(zapper, 1_000_000_000_000n);
        const malloryWethBefore = await weth.balanceOf(mallory.address);
        let attackStart = secondEpochPoint - 30n;
        const attackPrepBlock = await ethers.provider.getBlock('latest');
        const currentTsAttackPrep = BigInt(attackPrepBlock?.timestamp ?? 0);
        if (attackStart <= currentTsAttackPrep) {
            attackStart = currentTsAttackPrep + 30n;
        }
        await networkHelpers.time.increaseTo(attackStart);
        const attackSize = 10_000_000n;
        //      await zapper.connect(mallory).buy(weth, attackSize, 0n, Date.now());
        const malloryWethAfter = await weth.balanceOf(mallory.address);
        const wethSpent = malloryWethBefore - malloryWethAfter;

        console.log("mallory claimable bonus:", await favorEth.pendingBonus(mallory));

        const [res0, res1] = await favorWethPair.getReserves();
        const favorAddr = (await favorEth.getAddress()).toLowerCase();
        const token0Addr = (await favorWethPair.token0()).toLowerCase();
        const oneEther = 1_000_000_000_000_000_000n;
        const favorIsToken0 = token0Addr === favorAddr;
        const spotAfterAttack = favorIsToken0
            ? (BigInt(res1.toString()) * oneEther) / BigInt(res0.toString())
            : (BigInt(res0.toString()) * oneEther) / BigInt(res1.toString());
        console.log("Mallory spends", wethSpent.toString(), "WETH to push spot price to", spotAfterAttack.toString());

        let settlementTarget = secondEpochPoint + 5n;
        const settlementBlock = await ethers.provider.getBlock('latest');
        const currentTsSettlement = BigInt(settlementBlock?.timestamp ?? 0);
        if (settlementTarget <= currentTsSettlement) {
            settlementTarget = currentTsSettlement + 5n;
        }
        await networkHelpers.time.increaseTo(settlementTarget);
        await favorTreasury.connect(mallory).allocateSeigniorage();
        const manipulatedPrice = await favorTreasury.getFavorPrice();
        console.log("Treasury samples manipulated TWAP:", manipulatedPrice.toString());

        const groveBalanceAfterAttack = await favorEth.balanceOf(grove);
        console.log("Grove Favor balance after attack mint:", groveBalanceAfterAttack.toString());

        const alicePending = await grove.earned(alice.address);
        const malloryPending = await grove.earned(mallory.address);
        console.log("Alice pending reward post-attack:", alicePending.toString());
        console.log("Mallory pending reward post-attack:", malloryPending.toString());

        await grove.connect(mallory).claimReward();
        const malloryFavorAfterClaim = await favorEth.balanceOf(mallory.address);
        console.log("Mallory claims attacker reward, Favor received:", malloryFavorAfterClaim.toString());

        expect(manipulatedPrice).to.be.gt(baselinePrice);
        expect(malloryPending).to.be.gt(aliceBaselineReward / 2n); // attacker earns half of a huge issuance
        expect(malloryPending).to.be.gt(wethSpent * 1_000_000_000_000_000n); // dwarfs cost even before unwinding
    });


})