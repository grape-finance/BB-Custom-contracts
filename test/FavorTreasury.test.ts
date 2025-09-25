import {expect} from "chai";
import {network} from "hardhat";
import {ZeroAddress} from "ethers";
import {createToken, createUSV2Factory, createUSV2Router} from "./utils/contractUtils.js";

const {ethers, networkHelpers} = await network.connect();


describe('FavorTreasury.sol', () => {

    async function deployContracts() {

        const [deployer, owner, treasury, esteem] = await ethers.getSigners();


        let genesis = (await ethers.provider.getBlock('latest'))?.timestamp || 0;
        const epochKeeper = await ethers.deployContract("EpochKeeper", [genesis, 3600, owner]);

        const favorTreasuryInstance = await ethers.deployContract("FavorTreasury", [epochKeeper, owner]);
        let favorTreasury = favorTreasuryInstance.connect(owner);

        let weth = await createToken(owner, 'wethweth', "t0");
        let foo = await createToken(owner, 'foo', "foo");

        let v2factory = await createUSV2Factory(owner);
        let v2router = await createUSV2Router(owner, v2factory, weth);

        const favorEth = await ethers.deployContract("Favor", [owner, "FavorPLS", "fPLS", 1_000_000_000_000_000_000_000_000_000_000_000n, treasury, esteem]);

        await v2factory.createPair(favorEth, weth);
        await v2factory.createPair(foo, weth);

        let pairAdr = await v2factory.getPair(favorEth, weth);
        let favorWethPair = await ethers.getContractAt("IUniswapV2Pair", pairAdr, owner);

        pairAdr = await v2factory.getPair(foo, weth);
        let fooWethPair = await ethers.getContractAt("IUniswapV2Pair", pairAdr, owner);

        return {favorTreasury, epochKeeper, fooWethPair, favorWethPair, favorEth};
    }

    describe('deployment', () => {

        it("shall be able to deploy", async () => {
            const [deployer, owner] = await ethers.getSigners();
            let {favorTreasury, epochKeeper} = await deployContracts();

            expect(favorTreasury).to.not.equal(null);
            expect(await favorTreasury.owner()).to.equal(owner.address);

            let [current, from, to] = await epochKeeper.currentEpochBoundary();

            //  epoch 0  upon initalisation
            expect(await favorTreasury.nextEpochPoint()).to.equal(to);
        })
    })

    describe('access control', () => {

        it("only owner shall be able to call those methods", async () => {
            const [deployer, owner, notOwner] = await ethers.getSigners();
            let {favorTreasury} = await deployContracts();

            let notOwned = favorTreasury.connect(notOwner);

            // all those all shall fail
            await expect(notOwned.initialize(owner, owner, owner)).to.be.revertedWithCustomError(favorTreasury, "OwnableUnauthorizedAccount");
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
            let {favorTreasury, epochKeeper} = await deployContracts();

            let [current, from, to] = await epochKeeper.currentEpochBoundary();


            await expect(favorTreasury.initialize(favor, oracle, groove)).to.emit(favorTreasury, "Initialized");

            expect(await favorTreasury.isInitialized()).to.equal(true);
        })

        it('shall add and remove excluded address properly', async () => {

            const [deployer, owner, favor, oracle, groove] = await ethers.getSigners();
            let {favorTreasury} = await networkHelpers.loadFixture(deployContracts);

            await expect(favorTreasury.addExcludedAddress(favor)).to.emit(favorTreasury, "ExcludedAddressAdded").withArgs(favor);
            await expect(favorTreasury.addExcludedAddress(oracle)).to.emit(favorTreasury, "ExcludedAddressAdded").withArgs(oracle);
            await expect(favorTreasury.addExcludedAddress(groove)).to.emit(favorTreasury, "ExcludedAddressAdded").withArgs(groove);

            await (expect(favorTreasury.addExcludedAddress(favor))).to.be.revertedWith("Address already excluded");
            await (expect(favorTreasury.addExcludedAddress(ZeroAddress))).to.be.revertedWith('Cannot exclude zero address');


            await (expect(favorTreasury.removeExcludedAddress(owner))).to.be.revertedWith('Address not excluded');


            await (expect(favorTreasury.removeExcludedAddress(favor))).to.emit(favorTreasury, "ExcludedAddressRemoved").withArgs(favor);


            expect(await favorTreasury.excludedAddresses(0)).to.be.equal(groove);
            expect(await favorTreasury.excludedAddresses(1)).to.be.equal(oracle);

        })


        it('shall add and remove excluded pairs', async () => {

            const [deployer, owner, favor, oracle, groove] = await ethers.getSigners();
            let {
                favorTreasury,
                favorWethPair,
                fooWethPair,
                favorEth
            } = await networkHelpers.loadFixture(deployContracts);

            await expect(favorTreasury.initialize(favorEth, oracle, groove)).to.emit(favorTreasury, "Initialized");

            await expect(favorTreasury.addLpPairToExclude(favorWethPair)).to.emit(favorTreasury, "LpPairToExcludeAdded").withArgs(favorWethPair);
            await expect(favorTreasury.addLpPairToExclude(favorWethPair)).to.be.revertedWith('Pair already added');
            await expect(favorTreasury.addLpPairToExclude(ZeroAddress)).to.be.revertedWith("Zero pair");

            await expect(favorTreasury.addLpPairToExclude(fooWethPair)).to.be.revertedWith("Pair missing FAVOR");


            await expect(favorTreasury.removeLpPairToExclude(owner)).to.be.revertedWith('Pair not present');

            await expect(favorTreasury.removeLpPairToExclude(favorWethPair)).to.emit(favorTreasury, "LpPairToExcludeRemoved").withArgs(favorWethPair);
            await expect(favorTreasury.removeLpPairToExclude(favorWethPair)).to.be.revertedWith('Pair not present');
        })
    })

    describe('epoch transition', () => {
        it("seignorage allocation shall not happen before expoh end", async () => {
            const [deployer, owner, favor, oracle, groove] = await ethers.getSigners();
            let {favorTreasury, epochKeeper} = await networkHelpers.loadFixture(deployContracts);

            expect(await favorTreasury.allocateSeigniorage()).to.not.be.revert(ethers);
        })
    })
})