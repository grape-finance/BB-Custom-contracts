import {expect} from "chai";
import {network} from "hardhat";
import {ZeroAddress} from "ethers";
import {createToken, createUSV2Factory, createUSV2Router} from "./utils/contractUtils.js";
import {pool} from "@aave/core-v3/dist/types/types/protocol/index.js";
import hardhatNetworkHelpersPlugin from "@nomicfoundation/hardhat-network-helpers";

const {ethers} = await network.connect();


describe("Zapper.sol", () => {

    async function deployContracts() {
        const [deployer, owner, treasury] = await ethers.getSigners();

        const esteemInstance = await ethers.deployContract("Esteem", [owner]);
        let esteem = esteemInstance.connect(owner);

        const minter = await ethers.deployContract("MockEsteemMinter");
        // 0.1 ,  18 digitts fixed decimal point
        await minter.setEsteemRate(100000000000000000n)

        let weth = await createToken(owner, 'wethweth', "t0");
        let baseToken = await createToken(owner, 'baseTooke', "b0");

        let v2factory = await createUSV2Factory(owner);
        let v2router = await createUSV2Router(owner, v2factory, weth);


        const zapperInstance = await ethers.deployContract("LPZapper", [owner, weth, v2router]);
        let zapper = zapperInstance.connect(owner);

        const favorInstance = await ethers.deployContract("FavorPLS", [owner, 123_000_000_000_000_000_000_000_000n, treasury, esteem]);
        let favorEth = favorInstance.connect(owner);
        await favorEth.setPriceProvider(minter);
        await esteem.addMinter(favorEth);
        await minter.setTokenPrice(favorEth, 7_000_000_000_000_000_000n);

        const baseFavorInstance = await ethers.deployContract("FavorPLS", [owner, 123_000_000_000_000_000_000_000_000n, treasury, esteem]);
        let favorBase = baseFavorInstance.connect(owner);
        await favorBase.setPriceProvider(minter);
        await esteem.addMinter(favorBase);
        await minter.setTokenPrice(favorBase, 5_000_000_000_000_000_000n);


        await favorEth.setTaxExempt(zapper, true);
        // to be able to create LPs for test pusposes
        await favorEth.setTaxExempt(owner, true);
        await favorEth.setBuyWrapper(zapper, true);

        await favorBase.setTaxExempt(zapper, true);
        await favorBase.setTaxExempt(owner, true);
        await favorBase.setBuyWrapper(zapper, true);

        //  create weth / favor  liquidity pool
        await favorEth.approve(v2router, 1_000_000_000_000_000_000n);
        await weth.approve(v2router, 1_000_000_000_000_000_000n);


        // pair
        await v2factory.createPair(favorEth, weth);
        let pairAdr = await v2factory.getPair(favorEth, weth);

        let favorWethPair = await ethers.getContractAt("IUniswapV2Pair", pairAdr, owner);

        // and another liqiodity pool
        await favorBase.approve(v2router, 1_000_000_000_000_000_000n);
        await baseToken.approve(v2router, 1_000_000_000_000_000_000n);

        await v2factory.createPair(favorBase, baseToken);
        pairAdr = await v2factory.getPair(favorEth, weth);
        let favorBasePair = await ethers.getContractAt("IUniswapV2Pair", pairAdr, owner);


        // register this pair as favor pair
        await zapper.addFavor(favorEth, favorWethPair, weth);
        await zapper.addFavor(favorBase, favorBasePair, baseToken);

        await v2router.addLiquidity(favorEth, weth, 1000000n, 2000000n, 0n, 0n, owner, Date.now() + 100000)

        console.log("reservers", await favorWethPair.getReserves());

        // remove tax exempt status from owner
        await favorEth.setTaxExempt(owner, false);
        await favorBase.setTaxExempt(owner, false);


        // mock pool to test flash loans
        const mockPoolInstance = await ethers.deployContract("MockPool", []);
        let mockPool = mockPoolInstance.connect(owner);


        await zapper.setPool(mockPool);

        return {
            zapper,
            favorEth: favorEth,
            weth,
            favorWethPair,
            v2router,
            mockPool,
            baseToken,
            favorBase,
            favorBasePair,
            esteem
        };
    }

    describe(' deployment', () => {

        it("Should be able to create contract", async () => {
            const [deployer, owner] = await ethers.getSigners();
            let {zapper, weth, v2router} = await deployContracts();

            await expect(await zapper.router()).to.be.equal(v2router);
            await expect(await zapper.PLS()).to.be.equal(weth);

        })
    })

    describe('access control', () => {

        it("only owner methods", async () => {
            const [deployer, owner, somebody] = await ethers.getSigners();
            let {zapper} = await deployContracts();
            //Revert function because user is not the owner
            await expect(zapper.connect(somebody).addDustToken(somebody)).to.be.revertedWithCustomError(zapper, "OwnableUnauthorizedAccount");
            await expect(zapper.connect(somebody).removeDustToken(somebody)).to.be.revertedWithCustomError(zapper, "OwnableUnauthorizedAccount");
            await expect(zapper.connect(somebody).addFavor(somebody, somebody, somebody)).to.be.revertedWithCustomError(zapper, "OwnableUnauthorizedAccount");
            await expect(zapper.connect(somebody).adminWithdraw(somebody, somebody, 1n)).to.be.revertedWithCustomError(zapper, "OwnableUnauthorizedAccount");
            await expect(zapper.connect(somebody).adminWithdrawPLS(somebody, 1n)).to.be.revertedWithCustomError(zapper, "OwnableUnauthorizedAccount");
            await expect(zapper.connect(somebody).removeFavorToken(somebody)).to.be.revertedWithCustomError(zapper, "OwnableUnauthorizedAccount");
            await expect(zapper.connect(somebody).setPool(somebody)).to.be.revertedWithCustomError(zapper, "OwnableUnauthorizedAccount");
            await expect(zapper.connect(somebody).setAddressProvider(somebody)).to.be.revertedWithCustomError(zapper, "OwnableUnauthorizedAccount");

        })

        //  msg sender shall be a registered pool only
        it("shall no allow invocation from a wrong pool", async () => {
            const [deployer, owner, somebody] = await ethers.getSigners();
            let {zapper, favorEth} = await deployContracts();

            await expect(zapper.executeOperation(favorEth, 0n, 0n, somebody, "0x")).to.be.revertedWith("not registered pool");
        })

        //  if the pool is registered, initiator shall be a contract itself
        //  we trust aave pol that it does the right thing here.
        it("shall no allow invocation from a wrong pool caller", async () => {
            const [deployer, owner, somebody, pool] = await ethers.getSigners();
            let {zapper, favorEth} = await deployContracts();

            await zapper.setPool(pool);

            await expect(zapper.connect(pool).executeOperation(favorEth, 0n, 0n, somebody, "0x")).to.be.revertedWith("bad initiator");
        })
    })

    describe('token managements', () => {

        it('manage dust tokens', async () => {
            const [deployer, owner, somebody] = await ethers.getSigners();
            let {zapper} = await deployContracts();
            //Add dust token
            await expect(zapper.addDustToken(somebody)).to.not.be.revert(ethers);
            expect(await zapper.isDustToken(somebody)).to.be.equal(true);

            await expect(zapper.removeDustToken(somebody)).to.not.be.revert(ethers);
            expect(await zapper.isDustToken(somebody)).to.be.equal(false);

        })

        it("mabage favor tokens", async () => {
            const [deployer, owner, favor, lp, base] = await ethers.getSigners();
            let {zapper} = await deployContracts();

            // add favor token to favor
            expect(await zapper.addFavor(favor, lp, base)).to.not.be.revert(ethers);

            // shall have set up mappings
            expect(await zapper.tokenToFavor(base)).to.be.equal(favor);
            expect(await zapper.favorToLp(favor)).to.be.equal(lp);
            expect(await zapper.favorToToken(favor)).to.be.equal(base);

            //  shall remove favor mapping
            expect(await zapper.removeFavorToken(favor)).to.not.be.revert(ethers);

            // shall have removed mappings
            expect(await zapper.tokenToFavor(base)).to.be.equal(ZeroAddress);
            expect(await zapper.favorToLp(favor)).to.be.equal(ZeroAddress);
            expect(await zapper.favorToToken(favor)).to.be.equal(ZeroAddress);

        })


        it("shall withdraw tokens as admin", async () => {
            const [deployer, owner, receiver] = await ethers.getSigners();
            let {zapper, favorEth} = await deployContracts();

            await favorEth.transfer(zapper, 1000n);

            expect(await favorEth.balanceOf(zapper)).to.equal(1000n);
            await zapper.adminWithdraw(favorEth, receiver, 1000n);

            expect(await favorEth.balanceOf(zapper)).to.equal(0n);
            expect(await favorEth.balanceOf(receiver)).to.equal(1000n);

        })

    })

    describe('zapping operation', () => {
        it('shall not allow flash loan for unknoww tokens', async () => {
            const [deployer, owner, somebody] = await ethers.getSigners();

            let {zapper, favorEth, weth} = await deployContracts();

            await expect(zapper.requestFlashLoan(12345n, somebody)).to.be.revertedWith('Zapper: unsupported token');

        })

        it('shall request flash loan properly', async () => {

            const [deployer, owner] = await ethers.getSigners();
            let {zapper, favorEth, weth, mockPool, favorWethPair} = await deployContracts();

            //  there shall be enough alowance of favor
            await favorEth.approve(zapper, 1_000_000_000_000_000n);
            await expect(zapper.requestFlashLoan(12345n, favorEth)).to.not.be.revert(ethers);

            //  there shall be amount of favor on balance of zapper
            expect(await favorEth.balanceOf(zapper)).to.equal(12345n);

            //  shall have passes  correct params to mock  pool
            // callback to zapper itsel
            expect(await mockPool.receiverAddress()).to.equal(zapper);
            // loaning weth
            expect(await mockPool.receiverAddress()).to.equal(zapper);
            // proper counterpart token amount
            expect(await mockPool.amount()).to.equal(24690n);
            // properly encoded parameters
            let enc = await mockPool.params();
            let result = ethers.AbiCoder.defaultAbiCoder().decode(["address", "address", "address"], enc);
            expect(result[0]).to.equal(owner);
            expect(result[1]).to.equal(favorEth);
            expect(result[2]).to.equal(favorWethPair);

            // no referral code
            expect(await mockPool.referralCode()).to.equal(0);
            // shall set up pending user for the attack prevention
            expect(await zapper.pendingUser()).to.equal(owner);
        })

        // in case other user simulates flash loan,execution shall be reverted
        it('shall refuse operation if invoked fron not registered pool', async () => {

            const [deployer, owner] = await ethers.getSigners();
            let {zapper, weth} = await deployContracts();

            await expect(zapper.executeOperation(weth, 123n, 456, owner, "0x")).to.be.revertedWith("not registered pool");
        })

        it('shall refuse operation if invoked fron wrong initiator', async () => {
            const [deployer, owner] = await ethers.getSigners();

            let {zapper, favorEth, weth, mockPool, favorWethPair} = await deployContracts();

            await expect(mockPool.mockLoanFromWrongInitiator(zapper, owner)).to.be.revertedWith("bad initiator");
        })

        // in case stored user does not match, operation shall be refused
        it('shall refuse operation  if user does not match', async () => {

            const [deployer, owner] = await ethers.getSigners();
            let {zapper, weth, favorEth, mockPool} = await deployContracts();


            // simulate first part of onvocation
            //   we shall  have "owner"  recorded as pending user
            await favorEth.approve(zapper, 1_000_000_000_000_000n);
            await expect(zapper.requestFlashLoan(12345n, favorEth)).to.not.be.revert(ethers);

            await expect(mockPool.mockLoanFromWrongUser(zapper, deployer)).to.be.revertedWith("user mismatch");

        })


        it('shall perform borrowing operation', async () => {

            const [deployer, owner] = await ethers.getSigners();
            let {zapper, weth, favorEth, mockPool, favorWethPair} = await deployContracts();


            // simulate first part of onvocation
            //   we shall  have "owner"  recorded as pending user
            await favorEth.approve(zapper, 1_000_000_000_000_000n);
            await expect(zapper.requestFlashLoan(12345n, favorEth)).to.not.be.revert(ethers);

            //  before invoking, we shall provide amounts for LP creation
            await favorEth.transfer(zapper, 1000n);
            await weth.transfer(zapper, 2000n);

            await expect(mockPool.mockExecute(zapper, owner, weth, 2000, 200, favorEth, favorWethPair)).to.not.be.revert(ethers);

            //  there shall be chages

            // pendign user shall be reset
            expect(await zapper.pendingUser()).to.equal(ZeroAddress);

            //  there shall be LP created for the zapper,  1000 favor and 2000 weth are transdferred to the pair
            expect(await favorWethPair.balanceOf(zapper)).to.equal(1414n);
            expect(await favorEth.balanceOf(favorWethPair)).to.equal(1001000n);
            expect(await weth.balanceOf(favorWethPair)).to.equal(2002000n);

            // this amount ought to be approved for the pool to take
            expect(await favorWethPair.allowance(zapper, mockPool)).to.equal(1414n);

            //  therre shall be approwal for  weth to repay loan  amount + premoum
            expect(await weth.allowance(zapper, mockPool)).to.equal(2200n);


            // invocations shall be done

            // supply
            expect(await mockPool.supplyCalled()).to.be.equal(true);
            expect(await mockPool.assetSupplied()).to.be.equal(favorWethPair);
            expect(await mockPool.amountSupplied()).to.be.equal(1414n);
            expect(await mockPool.suppliedTo()).to.be.equal(owner);
            expect(await mockPool.supplyReferral()).to.be.equal(0);

// borrow
            expect(await mockPool.borrowCalled()).to.be.equal(true);
            expect(await mockPool.assetBorrowed()).to.be.equal(weth);
            // borrowed enough to repay the flash loan with premium
            expect(await mockPool.amountBorrowed()).to.be.equal(2200);
            expect(await mockPool.interestRateMode()).to.be.equal(2);
            expect(await mockPool.borrowReferral()).to.be.equal(0);
            expect(await mockPool.borrowedFrom()).to.be.equal(owner);

        })
    })


    describe('zapping', () => {

        it('zap  tokens  into LP', async () => {
            const [deployer, owner] = await ethers.getSigners();
            let {zapper, favorEth, weth, favorWethPair, esteem, mockPool} = await deployContracts();


            // approve 10000 weth to zapper
            await weth.approve(zapper, 10000n);

            //  shall take 10000 weth, change 5000 to  2500  favor,   and supply liquidity
            await expect(zapper.zapToken(weth, 10000n, Date.now() + 10000)).to.not.be.revert(ethers);



            // there shall be  balance, in real life it would be transferred away
            expect(await favorWethPair.balanceOf(zapper)).to.equal(3523n);

            //  shall have supplied LP to mock pool
            expect(await mockPool.supplyCalled()).to.be.equal(true);
            expect(await mockPool.assetSupplied()).to.be.equal(favorWethPair);
            expect(await mockPool.amountSupplied()).to.be.equal(3523n);
            expect(await mockPool.suppliedTo()).to.be.equal(owner);


            //  shall not withdraw favor tokens
            expect(await favorEth.balanceOf(owner)).to.equal(122999999999999999999000000n);
            // but 10000 weth shall be withdrawn
            expect(await weth.balanceOf(owner)).to.equal(999999999999999999997990000n);

            // there shall be esteem minting to treasury
            expect(await esteem.balanceOf(await favorEth.treasury())).to.equal(19140n);
            //  and pending esteem bonus for owner
            expect(await favorEth.pendingBonus(owner)).to.equal(76560n);
        })

        it('zap  Favor tokens  into LP', async () => {
            const [deployer, owner, receiver] = await ethers.getSigners();
            let {zapper, favorBase, baseToken, favorBasePair} = await deployContracts();

            expect(await zapper.tokenToFavor(baseToken)).to.be.equal(favorBase);
            // approve 10000 favor to zapper
            await favorBase.approve(zapper, 10000n);

            //  shall take 10000 base token, change 5000 to  2500  favor,   and supply liquidity
            await expect(zapper.zapFavor(baseToken, 10000n, Date.now() + 10000)).to.not.be.revert(ethers);

            // there shall be a balance
            expect(await favorBasePair.balanceOf(owner)).to.equal(2500n);
            //  shall  withdraw  favor tokens
            expect(await favorBase.balanceOf(owner)).to.equal(5000n);
            // shall not touch base token eth balance
            expect(await baseToken.balanceOf(owner)).to.equal(5000n);

        })
    })
})
