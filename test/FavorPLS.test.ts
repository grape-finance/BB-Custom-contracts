import {expect} from "chai";
import {network} from "hardhat";

const {ethers} = await network.connect();


/**
 *   as favors  are derived from base class , this tests covers all the functionality
 *
 */
describe("FavorPLS.sol", () => {

    async function deployContracts() {
        const [deployer, owner, treasury, esteem] = await ethers.getSigners();

        const favorInstance = await ethers.deployContract("FavorPLS", [owner, 123_000_000_000_000_000_000_000_000n, treasury, esteem]);
        let favor = favorInstance.connect(owner);

        return {favor};
    }


    describe(' deployment', () => {
        it("Should be able to deploy and configure contract", async () => {
            const [deployer, owner, treasury, esteem] = await ethers.getSigners();
            let {favor} = await deployContracts();

            expect(await favor.name()).to.equal("Favor PLS");
            expect(await favor.symbol()).to.equal("fPLS");
            expect(await favor.owner()).to.equal(owner.address);

            expect(await favor.treasury()).to.equal(treasury.address);
            expect(await favor.esteem()).to.equal(esteem.address);
        })


        it("should mint initial supply to owner", async () => {
            const [deployer, owner] = await ethers.getSigners();
            let {favor} = await deployContracts();

            expect(await favor.balanceOf(owner)).equal(123_000_000_000_000_000_000_000_000n);

        })
    })


    describe('access control', () => {
        it("not owner shall not be able to call those methods", async () => {
            const [deployer, owner, notOwner] = await ethers.getSigners();
            let {favor} = await deployContracts();

            let notOwned = favor.connect(notOwner);

            await expect(notOwned.addMinter(owner)).to.be.revertedWithCustomError(favor, "OwnableUnauthorizedAccount");
            await expect(notOwned.removeMinter(owner)).to.be.revertedWithCustomError(favor, "OwnableUnauthorizedAccount");
            await expect(notOwned.setEsteem(owner)).to.be.revertedWithCustomError(favor, "OwnableUnauthorizedAccount");
            await expect(notOwned.setTreasury(owner)).to.be.revertedWithCustomError(favor, "OwnableUnauthorizedAccount");
            await expect(notOwned.setEsteemMinter(owner)).to.be.revertedWithCustomError(favor, "OwnableUnauthorizedAccount");
            await expect(notOwned.setSellTax(239n)).to.be.revertedWithCustomError(favor, "OwnableUnauthorizedAccount");
            await expect(notOwned.setBonusRates(239n, 23n)).to.be.revertedWithCustomError(favor, "OwnableUnauthorizedAccount");
            await expect(notOwned.setBuyWrapper(owner,true)).to.be.revertedWithCustomError(favor, "OwnableUnauthorizedAccount");
            await expect(notOwned.setTaxExempt(owner, true)).to.be.revertedWithCustomError(favor, "OwnableUnauthorizedAccount");

        })

        it("not mnter  shall not be able to call those methods", async () => {
            const [deployer, owner, notOwner] = await ethers.getSigners();
            let {favor} = await deployContracts();

            await expect(favor.mint(notOwner, 123n)).to.be.revertedWith('Not authorized to mint');

        })
    })

    describe('mint', () => {
        it("shall mint favor, set and reset minters", async () => {
            const [owner, minter, receiver] = await ethers.getSigners();
            let {favor} = await deployContracts();


            // shall set minter
            await expect(favor.addMinter(minter)).to.emit(favor, "MinterAdded").withArgs(minter.address);
            // shall mint
            await expect(favor.connect(minter).mint(receiver,555n)).to.not.be.revert(ethers);
            // receiver shall receive 555 favors
            expect(await  favor.balanceOf(receiver)).to.equal(555n);
            // shall disable minter
            await expect(favor.removeMinter(minter)).to.emit(favor, "MinterRemoved").withArgs(minter.address);

            // shall revert
            await expect(favor.connect(minter).mint(receiver, 123n)).to.be.revertedWith('Not authorized to mint');

        })
    })
})