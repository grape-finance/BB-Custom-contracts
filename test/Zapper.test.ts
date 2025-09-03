import {expect} from "chai";
import {network} from "hardhat";
import {ZeroAddress} from "ethers";
import {createToken, createUSV2Factory, createUSV2Router} from "./utils/contractUtils.js";
import {exec} from "node:child_process";

const {ethers} = await network.connect();


describe("Zapper.sol", () => {

    async function deployContracts() {
        const [deployer, owner, treasury, esteem] = await ethers.getSigners();


        let weth = await createToken(owner, 'wethweth', "t0");

        let v2factory = await createUSV2Factory(owner);
        let v2router = await createUSV2Router(owner, v2factory, weth);


        const zapperInstance = await ethers.deployContract("LPZapper", [owner, weth, v2router]);
        let zapper = zapperInstance.connect(owner);

        const favorInstance = await ethers.deployContract("FavorPLS", [owner, 123_000_000_000_000_000_000_000_000n, treasury, esteem]);
        let favor = favorInstance.connect(owner);
        await favor.setTaxExempt(zapper, true);
        await favor.setTaxExempt(owner, true);

        //  create proper liquidity pool
        await favor.approve(v2router, 1_000_000_000_000_000_000n);
        await weth.approve(v2router, 1_000_000_000_000_000_000n);

        // pair
        await v2factory.createPair(favor, weth);
        let pairAdr = await v2factory.getPair(favor, weth);

        let favorWethPair = await ethers.getContractAt("IUniswapV2Pair", pairAdr, owner);

        // register this pair as favor pair
        await zapper.addFavor(favor, favorWethPair, weth);

        await v2router.addLiquidity(favor, weth, 1000000n, 2000000n, 0n, 0n, owner, Date.now() + 100000)

        console.log("reservers", await favorWethPair.getReserves());

        // mock pool to test flash loans
        const mockPoolInstance = await ethers.deployContract("MockPool", []);
        let mockPool = mockPoolInstance.connect(owner);


        await zapper.setPool(mockPool);

        return {zapper, favor, weth, favorWethPair, v2router, mockPool};
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
            let {zapper, favor} = await deployContracts();

            await expect(zapper.executeOperation(favor, 0n, 0n, somebody, "0x")).to.be.revertedWith("not registered pool");
        })

        //  if the pool is registered, initiator shall be a contract itself
        //  we trust aave pol that it does the right thing here.
        it("shall no allow invocation from a wrong pool caller", async () => {
            const [deployer, owner, somebody, pool] = await ethers.getSigners();
            let {zapper, favor} = await deployContracts();

            await zapper.setPool(pool);

            await expect(zapper.connect(pool).executeOperation(favor, 0n, 0n, somebody, "0x")).to.be.revertedWith("bad initiator");
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
            let {zapper, favor} = await deployContracts();

            await favor.transfer(zapper, 1000n);

            expect(await favor.balanceOf(zapper)).to.equal(1000n);
            await zapper.adminWithdraw(favor, receiver, 1000n);

            expect(await favor.balanceOf(zapper)).to.equal(0n);
            expect(await favor.balanceOf(receiver)).to.equal(1000n);

        })

    })

    describe('zapping operation', () => {
        it('shall not allow flash loan for unknoww tokens', async () => {
            const [deployer, owner, somebody] = await ethers.getSigners();

            let {zapper, favor, weth} = await deployContracts();

            await expect(zapper.requestFlashLoan(12345n, somebody)).to.be.revertedWith('Zapper: unsupported token');

        })

        it('shall request flash loan properly', async () => {

            const [deployer, owner] = await ethers.getSigners();
            let {zapper, favor, weth, mockPool, favorWethPair} = await deployContracts();

            //  there shall be enough alowance of favor
            await favor.approve(zapper, 1_000_000_000_000_000n);
            await expect(zapper.requestFlashLoan(12345n, favor)).to.not.be.revert(ethers);

            //  there shall be amount of favor on balance of zapper
            expect(await favor.balanceOf(zapper)).to.equal(12345n);

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
            expect(result[1]).to.equal(favor);
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

            let {zapper, favor, weth, mockPool, favorWethPair} = await deployContracts();

            await expect(mockPool.mockLoanFromWrongInitiator(zapper, owner)).to.be.revertedWith("bad initiator");
        })

        // in case stored user does not match, operation shall be refused
        it('shall refuse operation  if user does not match', async () => {

            const [deployer, owner] = await ethers.getSigners();
            let {zapper, weth, favor, mockPool} = await deployContracts();


            // simulate first part of onvocation
            //   we shall  have "owner"  recorded as pending user
            await favor.approve(zapper, 1_000_000_000_000_000n);
            await expect(zapper.requestFlashLoan(12345n, favor)).to.not.be.revert(ethers);

            await expect(mockPool.mockLoanFromWrongUser(zapper, owner, deployer)).to.be.revertedWith("user mismatch");

        })
    })
})
