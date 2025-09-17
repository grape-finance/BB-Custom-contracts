import {network, tasks} from "hardhat";
import {createToken, createUSV2Factory, createUSV2Router} from "./utils/contractUtils.js";
import {expect} from "chai";
import {fail} from "node:assert";

const {ethers, networkHelpers} = await network.connect();

describe('OracleManipulator', () => {


    async function deployContracts() {
        const [owner, treasury, alice, bob] = await ethers.getSigners();

        let startTime = Math.floor(Date.now() / 1000);

        const esteem = await ethers.deployContract("Esteem", [owner]);
        await esteem.addMinter(owner);
        await esteem.mint(owner, 1000n);


        const minter = await ethers.deployContract("MintRedeemer", [esteem, startTime + 10, owner]);
        // 0.1 ,  18 digitts fixed decimal point
        await minter.setEsteemRate(100000000000000000n)


        let weth = await createToken(owner, 'wethweth', "t0");

        let v2factory = await createUSV2Factory(owner);
        let v2router = await createUSV2Router(owner, v2factory, weth);


        const zapperInstance = await ethers.deployContract("LPZapper", [owner, v2router]);
        let zapper = zapperInstance.connect(owner);

        // mock pool to test flash loans
        const mockPoolInstance = await ethers.deployContract("MockPool", []);
        let mockPool = mockPoolInstance.connect(owner);


        await zapper.setPool(mockPool);


        const favorInstance = await ethers.deployContract("Favor", [owner, "FavorPLS", "fPLS", 123_000_000_000_000_000_000_000_000n, treasury, esteem]);
        let favorEth = favorInstance.connect(owner);
        await favorEth.setPriceProvider(minter);
        await esteem.addMinter(favorEth);

        //  give alice a shitload of favor
        await favorEth.transfer(alice, 1_000_000_000_000n);

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


        const uniTwapOracle = await ethers.deployContract("UniTWAPOracle", [favorWethPair, 3600, startTime, 1000_000_000_000_000_000_000n]);


        //  create grove
        let grove = await ethers.deployContract("Staking", [owner]);
        // groove shall be tax exempt
        await favorEth.setTaxExempt(grove, true);

        //  create and inialise favor treasury,
        const favorTreasury = await ethers.deployContract("FavorTreasury", [owner]);
        favorEth.setTaxExempt(favorTreasury, true);

        let ts = (await ethers.provider.getBlock('latest'))?.timestamp || 0;
        await favorTreasury.initialize(favorEth, uniTwapOracle, grove, ts + 10);
        await networkHelpers.time.increaseTo(ts + 20);


        //  initialise staking and stack some favor
        await grove.initialize(favorEth, esteem, favorTreasury);
        // and ensure that something is stacked
        await esteem.approve(grove, 1000n);
        await grove.stake(1000n);

        //  favor treasury is allowed to consult and update  oracle
        await uniTwapOracle.setApprovedUser(favorTreasury, true);

        //  favro treasury shall be a minter  for favor
        await favorEth.addMinter(favorTreasury);

        //  treasury is aithorised to allocate seigniorage
        grove.setTreasuryOperator(favorTreasury);

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
             grove
        };
    }

    describe('manipulation  testing', () => {


        it('shall be able to resist maipulation', async () => {
            const [owner, tresury , alice, bob] = await ethers.getSigners();
            let {
                zapper,
                v2router,
                esteem,
                weth,
                favorWethPair,
                favorEth,
                favorTreasury,
                uniTwapOracle,
                grove
            } = await deployContracts()

            //  try update oracle
            await expect(uniTwapOracle.update()).to.not.be.revert(ethers);

            //  initial state,  1sr epoch
            await favorTreasury.allocateSeigniorage();

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
            await expect(zapper.connect(alice).sell(favorEth, 10_000_000n, Date.now())).to.not.be.revert(ethers);

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

              let favorPriceAfter = await  favorTreasury.getFavorPrice();

            console.log("favorPriceAfter:", favorPriceAfter.toString());
        })

    })


})