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

        const minter = await ethers.deployContract("MockEsteemMinter");

        await favor.setEsteemMinter(minter);

        return {favor, minter, owner, treasury, esteem};
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
            await expect(notOwned.setBuyWrapper(owner, true)).to.be.revertedWithCustomError(favor, "OwnableUnauthorizedAccount");
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
            await expect(favor.connect(minter).mint(receiver, 555n)).to.not.be.revert(ethers);
            // receiver shall receive 555 favors
            expect(await favor.balanceOf(receiver)).to.equal(555n);
            // shall disable minter
            await expect(favor.removeMinter(minter)).to.emit(favor, "MinterRemoved").withArgs(minter.address);

            // shall revert
            await expect(favor.connect(minter).mint(receiver, 123n)).to.be.revertedWith('Not authorized to mint');

        })
    })

    describe('settings', () => {
        it("shall change settings", async () => {
            const [deployer, owner, minter, receiver] = await ethers.getSigners();
            let {favor} = await deployContracts();


            await expect(favor.addMinter(owner)).to.emit(favor, "MinterAdded").withArgs(owner.address);
            expect(await favor.isMinter(owner)).to.equal(true);

            await expect(favor.removeMinter(owner)).to.emit(favor, "MinterRemoved").withArgs(owner.address);
            expect(await favor.isMinter(owner)).to.equal(false);

            await expect(favor.setEsteem(owner)).to.emit(favor, "EsteemTokenUpdated").withArgs(owner.address);
            expect(await favor.esteem()).to.equal(owner.address);

            await expect(favor.setTreasury(owner)).to.emit(favor, "TreasuryUpdated").withArgs(owner.address);
            expect(await favor.treasury()).to.equal(owner.address);

            await expect(favor.setEsteemMinter(owner)).to.emit(favor, "EsteemMinterUpdated").withArgs(owner.address);
            expect(await favor.esteemMinter()).to.equal(owner.address);


            await expect(favor.setSellTax(239n)).to.emit(favor, "SellTaxUpdated").withArgs(239n);
            expect(await favor.sellTax()).to.equal(239n);


            await expect(favor.setBonusRates(239n, 23n)).to.emit(favor, "BonusRatesUpdated").withArgs(239n, 23n);
            expect(await favor.bonusRate()).to.equal(239n);
            expect(await favor.treasuryBonusRate()).to.equal(23n);

            await expect(favor.setBuyWrapper(owner, true)).to.emit(favor, "BuyWrapperUpdated").withArgs(owner, true);
            expect(await favor.isBuyWrapper(owner)).to.equal(true);

            await expect(favor.setTaxExempt(owner, true)).to.emit(favor, "TaxExemptStatusUpdated").withArgs(owner, true);
            expect(await favor.isTaxExempt(owner)).to.equal(true);

        })
    })

    describe("calculations ", () => {
        it("should calculate proper favor bonuses", async () => {
            const [deployer, owner] = await ethers.getSigners();
            let {favor, minter} = await deployContracts();

            await minter.setTokenPrice(favor,11_000_000_000_000_000_000n);
            await minter.setEsteemRate(12_000_000_000_000_000_000n);


            let [userBonus, treasuryBonus] = await favor.calculateFavorBonuses(100_000_000_000_000_000_000n);

            expect(userBonus).to.equal(40333333333333333333n);
            expect(treasuryBonus).to.equal(10083333333333333333n);
        })

        it("shall revert bonus calculation if esteem rate is 0", async () => {
            const [deployer, owner] = await ethers.getSigners();
            let {favor, minter} = await deployContracts();

            await minter.setEsteemRate(0n);
            await minter.setTokenPrice(favor,17_000_000_000_000_000_000n);


            await expect(favor.calculateFavorBonuses(100_000_000_000_000_000_000n)).to.be.revertedWith('Invalid Esteem rate');

        })
    })
})