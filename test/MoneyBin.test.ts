import {expect} from "chai";
import {network} from "hardhat";
import {ZeroAddress} from "ethers";
import {createToken, createUSV2Factory, createUSV2Router} from "./utils/contractUtils.js";
import {fail} from "node:assert";

const {ethers, networkHelpers} = await network.connect();


describe('MoneyBin.sol', () => {

    async function deployContracts() {
        const [owner, executor, receiver] = await ethers.getSigners();



        let weth = await createToken(owner, 'wethweth', "t0");
        let baseToken = await createToken(owner, 'baseTooke', "b0");

        let v2factory = await createUSV2Factory(owner);
        let v2router = await createUSV2Router(owner, v2factory, weth);


        const moneyBin = await ethers.deployContract("MoneyBin", [owner, v2router, v2factory]);

        await moneyBin.setExecutor(executor, true);
        await moneyBin.setReceiver(receiver);

        await weth.transfer(moneyBin, 1_000_000_000_000_000_000n);

        return {moneyBin, weth, baseToken, v2factory, v2router};

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
            const [owner,  executor, receiver, whatever] = await ethers.getSigners();
            let {moneyBin} = await networkHelpers.loadFixture(deployContracts);

            expect(await moneyBin.isExecutor(whatever)).to.equal(false);
            await expect(moneyBin.setExecutor(whatever, true)).to.not.be.revert(ethers);
            expect(await moneyBin.isExecutor(whatever)).to.equal(true);
            await expect(moneyBin.setExecutor(whatever, false)).to.not.be.revert(ethers);
            expect(await moneyBin.isExecutor(whatever)).to.equal(false);

        })

    })


    describe('operations', () => {

        it('shall supply configured address on request', async () => {
                const [owner, executor, receiver] = await ethers.getSigners();
                let {moneyBin, weth} = await networkHelpers.loadFixture(deployContracts);

                await expect(moneyBin.connect(executor).supply(weth, 123n)).to.not.be.revert(ethers);
                expect(await  weth.balanceOf(receiver)).to.equal(123n);

            }
        )
        it('shall mint favoro and swap for asset', async () => {
            const [owner, somebody] = await ethers.getSigners();
            let {moneyBin} = await networkHelpers.loadFixture(deployContracts);
            fail('implement me');
        })
    })

})