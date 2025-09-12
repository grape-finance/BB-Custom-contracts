import {expect} from "chai";
import {network} from "hardhat";

const {ethers} = await network.connect();


describe('Staking.sol', () => {

    async function deployContracts() {

        const [owner] = await ethers.getSigners();

        const stakingInstance = await ethers.deployContract("Staking", [owner]);
        let staking = stakingInstance.connect(owner);

        return {staking};
    }

    describe('deployment', () => {

        it("shall be able to deploy", async () => {
            const [owner] = await ethers.getSigners();
            let {staking} = await deployContracts();

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
    })
})