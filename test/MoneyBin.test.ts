import {expect} from "chai";
import {network} from "hardhat";
import {ZeroAddress} from "ethers";
import {createToken, createUSV2Factory, createUSV2Router} from "./utils/contractUtils.js";
import {fail} from "node:assert";

const {ethers, networkHelpers} = await network.connect();


describe('MoneyBin.sol', () => {

    async function deployContracts() {
        const [owner, executor, receiver, treasury, esteem] = await ethers.getSigners();


        let weth = await createToken(owner, 'wethweth', "t0");
        let baseToken = await createToken(owner, 'baseTooke', "b0");

        let v2factory = await createUSV2Factory(owner);
        let v2router = await createUSV2Router(owner, v2factory, weth);


        const moneyBin = await ethers.deployContract("MoneyBin", [owner, v2router, v2factory]);

        await moneyBin.setExecutor(executor, true);
        await moneyBin.setReceiver(receiver);

        await weth.transfer(moneyBin, 1_000_000_000_000_000_000n);

        //  favor, money bin shall be able to mint favors  and be tax exempt
        const feth = await ethers.deployContract("Favor", [owner, "FavorPLS", "fPLS", 123_000_000_000_000_000_000_000_000n, treasury, esteem]);
        await feth.addMinter(moneyBin);
        await feth.setTaxExempt(moneyBin, true);


        await moneyBin.registerFavor(weth, feth);

        //  create weth / favor  liquidity pool
        await feth.approve(v2router, 1_000_000_000_000_000_000n);
        await weth.approve(v2router, 1_000_000_000_000_000_000n);

        // pair
        await v2factory.createPair(feth, weth);
        let pairAdr = await v2factory.getPair(feth, weth);

        let favorWethPair = await ethers.getContractAt("IUniswapV2Pair", pairAdr, owner);

        await feth.setTaxExempt(owner, true);
        await v2router.addLiquidity(feth, weth, 1000000n, 2000000n, 0n, 0n, owner, Date.now() + 100000);
        await feth.setTaxExempt(owner, false);


        return {moneyBin, weth, baseToken, v2factory, v2router, feth, favorWethPair};

    }

    describe('deployment', () => {
        it('shall deploy and configure properly', async () => {
            const [owner] = await ethers.getSigners();
            let {moneyBin, v2router, v2factory} = await networkHelpers.loadFixture(deployContracts);
            expect(await moneyBin.owner()).to.equal(owner.address);
            expect(await moneyBin.router()).to.equal(v2router);
            expect(await moneyBin.factory()).to.equal(v2factory);

        })
    })


    describe('access control', () => {

        it('only owner methods', async () => {
            const [owner, somebody, whatever] = await ethers.getSigners();
            let {moneyBin} = await networkHelpers.loadFixture(deployContracts);

            await expect(moneyBin.connect(somebody).setRouter(whatever)).to.be.revertedWithCustomError(moneyBin, "OwnableUnauthorizedAccount");
            await expect(moneyBin.connect(somebody).setFactory(whatever)).to.be.revertedWithCustomError(moneyBin, "OwnableUnauthorizedAccount");
            await expect(moneyBin.connect(somebody).setExecutor(whatever, false)).to.be.revertedWithCustomError(moneyBin, "OwnableUnauthorizedAccount");
            await expect(moneyBin.connect(somebody).setReceiver(whatever)).to.be.revertedWithCustomError(moneyBin, "OwnableUnauthorizedAccount");
            await expect(moneyBin.connect(somebody).withdraw(whatever, 1000, whatever)).to.be.revertedWithCustomError(moneyBin, "OwnableUnauthorizedAccount");
            await expect(moneyBin.connect(somebody).registerFavor(whatever, whatever)).to.be.revertedWithCustomError(moneyBin, "OwnableUnauthorizedAccount");
            await expect(moneyBin.connect(somebody).setThreshold(123n)).to.be.revertedWithCustomError(moneyBin, "OwnableUnauthorizedAccount");

        })

        it('only executor methods', async () => {
            const [owner, executor, somebody] = await ethers.getSigners();
            let {moneyBin} = await networkHelpers.loadFixture(deployContracts);

            await expect(moneyBin.supply(somebody, 123n)).to.be.revertedWith("MoneyBin: not executor");
        })
    })


    describe('setup', () => {
        it('shall set router', async () => {
            const [owner, somebody, whatever] = await ethers.getSigners();
            let {moneyBin} = await networkHelpers.loadFixture(deployContracts);

            await expect(moneyBin.setRouter(whatever)).to.not.be.revert(ethers);
            expect(await moneyBin.router()).to.equal(whatever);

        })

        it('shall set factory', async () => {
            const [owner, somebody, whatever] = await ethers.getSigners();
            let {moneyBin} = await networkHelpers.loadFixture(deployContracts);

            await expect(moneyBin.setRouter(whatever)).to.not.be.revert(ethers);
            expect(await moneyBin.router()).to.equal(whatever);

        })


        it('shall set receiver', async () => {
            const [owner, somebody, whatever] = await ethers.getSigners();
            let {moneyBin} = await networkHelpers.loadFixture(deployContracts);

            await expect(moneyBin.setReceiver(whatever)).to.not.be.revert(ethers);
            expect(await moneyBin.receiver()).to.equal(whatever);

        })


        it('shall set executor', async () => {
            const [owner, executor, receiver, whatever] = await ethers.getSigners();
            let {moneyBin} = await networkHelpers.loadFixture(deployContracts);

            expect(await moneyBin.isExecutor(whatever)).to.equal(false);
            await expect(moneyBin.setExecutor(whatever, true)).to.not.be.revert(ethers);
            expect(await moneyBin.isExecutor(whatever)).to.equal(true);
            await expect(moneyBin.setExecutor(whatever, false)).to.not.be.revert(ethers);
            expect(await moneyBin.isExecutor(whatever)).to.equal(false);

        })

        it('shall register favor', async () => {
            const [owner, favor, asset] = await ethers.getSigners();
            let {moneyBin} = await networkHelpers.loadFixture(deployContracts);

            await expect(moneyBin.registerFavor(asset, favor)).to.not.be.revert(ethers);
            expect(await moneyBin.asset2Favor(asset)).to.equal(favor);

        })

        it('shall set threshold', async () => {
            const [owner, executor, receiver, whatever] = await ethers.getSigners();
            let {moneyBin} = await networkHelpers.loadFixture(deployContracts);

            await expect(moneyBin.setThreshold(0)).to.be.revertedWith("MoneyBin: muste be above 0");
            await expect(moneyBin.setThreshold(10000)).to.be.revertedWith("MoneyBin: muste be below 10000");

            await expect(moneyBin.setThreshold(239)).to.not.be.revert(ethers);
            expect(await moneyBin.mintThreshold()).to.equal(239n);

        })
    })


    describe('operations', () => {

        it('shall supply configured address on request', async () => {
                const [owner, executor, receiver] = await ethers.getSigners();
                let {moneyBin, weth} = await networkHelpers.loadFixture(deployContracts);

                await expect(moneyBin.connect(executor).supply(weth, 123n)).to.not.be.revert(ethers);
                expect(await weth.balanceOf(receiver)).to.equal(123n);

            }
        )

        it("shall allow withdrawal of tokens", async () => {
            const [owner, executor, receiver] = await ethers.getSigners();
            const {moneyBin, weth} = await networkHelpers.loadFixture(deployContracts);


            await expect(moneyBin.withdraw(weth, 1000n, receiver)).to.emit(moneyBin, "Withdrawn").withArgs(weth, 1_000n, receiver);

            expect(await weth.balanceOf(receiver)).to.equal(1000n);
        })


        it('shall not mint if there s no favor registered', async () => {
            const [owner, somebody] = await ethers.getSigners();
            let {moneyBin} = await networkHelpers.loadFixture(deployContracts);

            //  shall mint favor and exchage to asset
            await  expect(moneyBin.mintAsset(somebody, 1000n)).to.be.revertedWith("MoneyBin: favor not registered");
        })

        it('shall mint enough favors and swap for asset', async () => {

            const [owner, somebody] = await ethers.getSigners();
            let {moneyBin, favorWethPair, weth, feth} = await networkHelpers.loadFixture(deployContracts);

            //  shall mint favor and exchage to asset
            expect(await moneyBin.mintAsset(weth, 1000n)).to.not.be.revert(ethers);
            //  1000 of asset shall be on our balance
            expect(await weth.balanceOf(moneyBin)).to.equal(1_000_000_000_000_000_000n + 1000n);

            //  pair shall have 1000 weth less
            expect(await weth.balanceOf(favorWethPair)).to.equal(1999000n);
            // and more favor
            expect(await feth.balanceOf(favorWethPair)).to.equal(1000502n);
        })
    })

})