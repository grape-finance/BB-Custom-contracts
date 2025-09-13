import {expect} from "chai";
import {network} from "hardhat";
import {ZeroAddress} from "ethers";
import {createToken, createUSV2Factory, createUSV2Router} from "./utils/contractUtils.js";

const {ethers} = await network.connect();


describe('FavorTreasury.sol', () => {

    async function deployContracts() {

        const [deployer, owner] = await ethers.getSigners();

        const favorTreasuryInstance = await ethers.deployContract("FavorTreasury", [owner]);
        let favorTreasury = favorTreasuryInstance.connect(owner);

        return {favorTreasury};
    }

    describe('deployment', () => {

        it("shall be able to deploy", async () => {
            const [deployer, owner] = await ethers.getSigners();
            let {favorTreasury} = await deployContracts();

            expect(favorTreasury).to.not.equal(null);
            expect(await favorTreasury.owner()).to.equal(owner.address);
        })
    })

    describe('access control', () => {

        it("only owner shall be able to call those methods", async () => {
            const [deployer, owner, notOwner] = await ethers.getSigners();
            let {favorTreasury} = await deployContracts();

            let notOwned = favorTreasury.connect(notOwner);

            // all those all shall fail
            await expect(notOwned.initialize(owner, owner, owner, 12345n)).to.be.revertedWithCustomError(favorTreasury, "OwnableUnauthorizedAccount");
            await expect(notOwned.setGrove(owner)).to.be.revertedWithCustomError(favorTreasury, "OwnableUnauthorizedAccount");
            await expect(notOwned.setFavorOracle(owner)).to.be.revertedWithCustomError(favorTreasury, "OwnableUnauthorizedAccount");
            await expect(notOwned.setMaxSupplyExpansionPercents(123)).to.be.revertedWithCustomError(favorTreasury, "OwnableUnauthorizedAccount");
            await expect(notOwned.setMinSupplyExpansionPercents(123)).to.be.revertedWithCustomError(favorTreasury, "OwnableUnauthorizedAccount");
            await expect(notOwned.addExcludedAddress(owner)).to.be.revertedWithCustomError(favorTreasury, "OwnableUnauthorizedAccount");
            await expect(notOwned.removeExcludedAddress(owner)).to.be.revertedWithCustomError(favorTreasury, "OwnableUnauthorizedAccount");
            await expect(notOwned.addLpPairToExclude(owner)).to.be.revertedWithCustomError(favorTreasury, "OwnableUnauthorizedAccount");
            await expect(notOwned.removeLpPairToExclude(owner)).to.be.revertedWithCustomError(favorTreasury, "OwnableUnauthorizedAccount");
            await expect(notOwned.pause()).to.be.revertedWithCustomError(favorTreasury, "OwnableUnauthorizedAccount");
            await expect(notOwned.unpause()).to.be.revertedWithCustomError(favorTreasury, "OwnableUnauthorizedAccount");
            await expect(notOwned.setExtraFunds(owner, 123)).to.be.revertedWithCustomError(favorTreasury, "OwnableUnauthorizedAccount");
            await expect(notOwned.governanceRecoverUnsupported(owner, 123, owner)).to.be.revertedWithCustomError(favorTreasury, "OwnableUnauthorizedAccount");

        })
    })

    describe('settings and initialisation', () => {
        it("shall initialise treasury", async () => {
            const [deployer, owner, favor, oracle, groove] = await ethers.getSigners();
            let {favorTreasury} = await deployContracts();

            let currentTime = Date.now();
            await expect(favorTreasury.initialize(favor, oracle, groove, currentTime)).to.emit(favorTreasury, "Initialized");

            expect(await  favorTreasury.isInitialized()).to.equal(true);
            //  epoch 0  upon initalisation
            expect(await  favorTreasury.nextEpochPoint()).to.equal(currentTime);
        })
    })
})