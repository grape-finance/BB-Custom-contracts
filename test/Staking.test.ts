import {expect} from "chai";
import {network} from "hardhat";

const {ethers} = await network.connect();


describe('Staking.sol', () => {

    async function deployContracts() {

        const [deployer, owner, treasury] = await ethers.getSigners();

        const stakingInstance = await ethers.deployContract("Staking", [owner]);
        let staking = stakingInstance.connect(owner);

        const esteemInstance = await ethers.deployContract("Esteem", [owner]);
        let esteem = esteemInstance.connect(owner);

        const favorInstance = await ethers.deployContract("Favor", [owner, "FavorPLS", "fPLS", 123_000_000_000_000_000_000_000_000n, treasury, esteem]);
        let favor = favorInstance.connect(owner);

        await favor.setTaxExempt(staking, true);
        return {staking, favor, esteem};
    }

    describe('deployment', () => {

        it("shall be able to deploy", async () => {
            const [deployer, owner] = await ethers.getSigners();
            let {staking} = await deployContracts();

            expect(staking).to.not.equal(null);
            expect(await staking.owner()).to.equal(owner.address);
        })
    })

    describe('access control', () => {

        it("only owner shall be able to call those methods", async () => {
            const [deployer, owner, notOwner, treasuryOperator] = await ethers.getSigners();
            let {staking} = await deployContracts();

            let notOwned = staking.connect(notOwner);

            // all those all shall fail
            await expect(notOwned.initialize(owner, owner, owner)).to.be.revertedWithCustomError(staking, "OwnableUnauthorizedAccount");
            await expect(notOwned.setTreasuryOperator(owner)).to.be.revertedWithCustomError(staking, "OwnableUnauthorizedAccount");
            await expect(notOwned.pause()).to.be.revertedWithCustomError(staking, "OwnableUnauthorizedAccount");
            await expect(notOwned.unpause()).to.be.revertedWithCustomError(staking, "OwnableUnauthorizedAccount");
            await expect(notOwned.governanceRecoverUnsupported(owner, 123, owner)).to.be.revertedWithCustomError(staking, "OwnableUnauthorizedAccount");
            await expect(notOwned.allocateSeigniorage(123n)).to.be.revertedWith("Not authorized");

        })
    })

    describe('settings and initialisation', () => {

        it('shall not be able to initialise if not tax exempt', async () => {
            const [deployer, owner, treasury] = await ethers.getSigners();
            let {staking, favor, esteem} = await deployContracts();

            await favor.setTaxExempt(staking, false);
            await expect(staking.initialize(favor, esteem, treasury)).to.revertedWith("Grove: not tax exempt");


        })

        it('shall initialise only once', async () => {
            const [deployer, owner, treasury] = await ethers.getSigners();
            let {staking, favor, esteem} = await deployContracts();

            //  first shall go
            await expect(staking.initialize(favor, esteem, treasury)).to.not.be.revert(ethers);
            await expect(staking.initialize(favor, esteem, treasury)).to.be.revertedWith("Grove: already initialized");

        })


        it('shall initialise properly', async () => {
            const [deployer, owner, treasury] = await ethers.getSigners();
            let {staking, favor, esteem} = await deployContracts();

            //  first shall go
            await expect(staking.initialize(favor, esteem, treasury)).to.emit(staking, "Initialized")
            expect(await staking.treasury()).to.equal(treasury.address);
            expect(await staking.favor()).to.equal(favor);
            expect(await staking.esteem()).to.equal(esteem);
            expect(await staking.treasuryOperator()).to.equal(treasury.address);
        })
    })
})