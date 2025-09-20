import {expect} from "chai";
import {network} from "hardhat";

const {ethers, networkHelpers} = await network.connect();


describe('Staking.sol', () => {

    async function deployContracts() {

        const [owner, treasury] = await ethers.getSigners();

        let genesis = (await ethers.provider.getBlock('latest'))?.timestamp || 0;
        const epochKeeper = await ethers.deployContract("EpochKeeper", [genesis, 3600, owner]);

        let nextEpochPoint = await epochKeeper.currentEpochEndTime();
        //  now go 1 minute before the current epoch
        await networkHelpers.time.increaseTo(nextEpochPoint + 1n);


        const staking = await ethers.deployContract("Staking", [epochKeeper, owner]);

        const esteem = await ethers.deployContract("Esteem", [owner]);
        await esteem.addMinter(owner);
        await esteem.mint(owner, 100000n);

        const favor = await ethers.deployContract("Favor", [owner, "FavorPLS", "fPLS", 123_000_000_000_000_000_000_000_000n, treasury, esteem]);

        await favor.setTaxExempt(staking, true);

        return {staking, favor, esteem, epochKeeper};
    }

    async function deployInitialised() {

        const [owner, treasury] = await ethers.getSigners();
        let {staking, favor, esteem, epochKeeper} = await deployContracts();

        await expect(staking.initialize(favor, esteem, treasury)).to.not.be.revert(ethers);

        return {staking, favor, esteem, epochKeeper};
    }

    describe('deployment', () => {

        it("shall be able to deploy", async () => {
            const [owner] = await ethers.getSigners();
            let {staking} = await networkHelpers.loadFixture(deployContracts);

            expect(staking).to.not.equal(null);
            expect(await staking.owner()).to.equal(owner.address);
        })
    })

    describe('access control', () => {

        it("only owner shall be able to call those methods", async () => {
            const [owner, notOwner, treasuryOperator] = await ethers.getSigners();
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

        it('shall not allow to call those methods when paused', async () => {

            const [owner, notOwner, treasuryOperator] = await ethers.getSigners();
            let {staking} = await networkHelpers.loadFixture(deployContracts);

            //  staking shall be paused
            await expect(staking.pause()).to.emit(staking, "Paused");
            expect(await staking.paused()).to.equal(true);

            //  shall not be able to invoke those methods
            await expect(staking.stake(12n)).to.be.revertedWithCustomError(staking, "EnforcedPause");
            await expect(staking.withdraw(12n)).to.be.revertedWithCustomError(staking, "EnforcedPause");
            await expect(staking.claimReward()).to.be.revertedWithCustomError(staking, "EnforcedPause");
            await expect(staking.allocateSeigniorage(123)).to.be.revertedWithCustomError(staking, "EnforcedPause");
        })
    })

    describe('settings and initialisation', () => {

        it('shall not be able to initialise if not tax exempt', async () => {
            const [owner, treasury] = await ethers.getSigners();
            let {staking, favor, esteem} = await networkHelpers.loadFixture(deployContracts);

            await favor.setTaxExempt(staking, false);
            await expect(staking.initialize(favor, esteem, treasury)).to.revertedWith("Grove: not tax exempt");


        })

        it('shall initialise only once', async () => {
            const [owner, treasury] = await ethers.getSigners();
            let {staking, favor, esteem} = await networkHelpers.loadFixture(deployContracts);

            //  first shall go
            await expect(staking.initialize(favor, esteem, treasury)).to.not.be.revert(ethers);
            await expect(staking.initialize(favor, esteem, treasury)).to.be.revertedWith("Grove: already initialized");

        })


        it('shall initialise properly', async () => {
            const [owner, treasury] = await ethers.getSigners();
            let {staking, favor, esteem} = await networkHelpers.loadFixture(deployContracts);

            //  first shall go
            await expect(staking.initialize(favor, esteem, treasury)).to.emit(staking, "Initialized")
            expect(await staking.treasury()).to.equal(treasury.address);
            expect(await staking.favor()).to.equal(favor);
            expect(await staking.esteem()).to.equal(esteem);
            expect(await staking.treasuryOperator()).to.equal(treasury.address);
        })
    })

    describe('staking', () => {
        // HAL-001
        // Halborn audit identified potential vulnerabiliy when stake is dobe before epoch cutoff:
        // In Staking contract allocateSeigniorage(amount) computes rewardPerShare using the live
        // totalSupply() at the time the function runs and immediately credits rewards to a new
        // snapshot. Because totalSupply() is read at allocation time, an attacker who sees a pending
        // allocateSeigniorage transaction can front-run it by staking a large amount right before the
        // allocation is executed. That attacker’s newly-staked balance becomes part of the denominator
        // used to split the reward, allowing the attacker to capture a disproportionate share of the
        // distribution, then withdraw immediately, the honest stakers receive only the leftover portion.
        //
        //  To prevent this, deposit locking shall be impleneted so that deposit can bewidthdrawn after  the next
        //  epoch ends.
        it('shall implement staking lock', async () => {
            const [owner, treasury, staker] = await ethers.getSigners();
            let {staking, favor, esteem, epochKeeper} = await networkHelpers.loadFixture(deployInitialised);

            let currentEpoch = await epochKeeper.currentEpoch();

            // there shall be no stake lock upon initalisation
            expect(await staking.isLocked()).to.equal(false);

            //  there shall be a stacking lock in place after deposit

            await expect(esteem.approve(staking, 10000000n)).to.not.be.revert(ethers);
            await expect(staking.stake(12345n)).to.not.be.revert(ethers);
            //  stake shall be in place
            expect(await staking.balanceOf(owner)).to.equal(12345n);

            // there shall be a lock till the end of epoch 2


            expect(await staking.isLocked()).to.equal(true);
            expect(await staking.stakeLock(owner)).to.equal(2n);
            await expect(staking.withdraw(124n)).to.be.revertedWith("Deposit locked");

            // lock shall be extended with a new deposit
            let epoch2Start = await epochKeeper.epochStart(2n);
            await networkHelpers.time.increaseTo(epoch2Start + 1n);
            await expect(staking.stake(12345n)).to.not.be.revert(ethers);

            expect(await staking.stakeLock(owner)).to.equal(3n);


            // epoch 4 shall have no restriction
            let epoch4Start = await epochKeeper.epochStart(4n);
            await networkHelpers.time.increaseTo(epoch4Start + 1n);

            await expect(staking.withdraw(1000n)).to.not.be.revert(ethers);
            expect(await staking.balanceOf(owner)).to.equal(23690n);

        })

    })


})