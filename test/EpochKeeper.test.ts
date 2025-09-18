import {network, tasks} from "hardhat";
import {createToken, createUSV2Factory, createUSV2Router} from "./utils/contractUtils.js";
import {expect} from "chai";
import {fail} from "node:assert";

const {ethers, networkHelpers} = await network.connect();

describe('EpochKeeper', () => {

    async function deployContracts() {
        const [deployer, owner] = await ethers.getSigners();

        let genesis = (await ethers.provider.getBlock('latest'))?.timestamp || 0;

        const epochKeeperInstance = await ethers.deployContract("EpochKeeper", [genesis, 1000, owner]);
        let epochKeeper = epochKeeperInstance.connect(owner);
        return {epochKeeper, genesis};
    }

    it('be deployed and configured', async () => {
        const [deployer, owner] = await ethers.getSigners();

        let {epochKeeper, genesis} = await networkHelpers.loadFixture(deployContracts);

        expect(await epochKeeper.owner()).to.equal(owner.address);
        expect(await epochKeeper.epochStartTime()).to.equal(genesis);

        expect(await epochKeeper.currentEpoch()).to.equal(0);

        let [current, from, to] = await epochKeeper.currentEpochBoundary();
        expect(current).to.equal(0n);
        expect(from).to.equal(genesis);
        expect(to).to.equal(genesis + 1000);
    })

    it('owner shall be able to change duration', async () => {
        const [deployer, owner, somebody] = await ethers.getSigners();

        let {epochKeeper} = await networkHelpers.loadFixture(deployContracts);

        //  shalll do
        await expect(epochKeeper.setEpochDuration(2000)).to.not.be.revert(ethers);
        expect(await epochKeeper.epochDuration()).to.equal(2000);

        // shall fail
        await expect(epochKeeper.connect(somebody).setEpochDuration(123n)).to.be.revertedWithCustomError(epochKeeper, "OwnableUnauthorizedAccount");
    })


    it('shall change epoch', async () => {
        const [deployer, owner, somebody] = await ethers.getSigners();

        let {epochKeeper} = await networkHelpers.loadFixture(deployContracts);

        let [current, from, to] = await epochKeeper.currentEpochBoundary();
        //  advance to the next epoch
        await networkHelpers.time.increaseTo(to - 10n);
        expect(await epochKeeper.currentEpoch()).to.equal(current);

        //  advance to the next epoch
        await networkHelpers.time.increaseTo(to + 1n);
        expect(await epochKeeper.currentEpoch()).to.equal(current +1n);
    })
});