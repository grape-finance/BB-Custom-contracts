import {expect} from "chai";
import {network} from "hardhat";
import {ZeroAddress} from "ethers";
import {createToken, createUSV2Factory, createUSV2Router} from "./utils/contractUtils.js";

const {ethers, networkHelpers} = await network.connect();


describe('Killswitch.sol', () => {

    async function deployContracts() {

        const [owner, treasury, esteem] = await ethers.getSigners();
        const killswitch = await ethers.deployContract("Killswitch", [2, owner]);

        return {killswitch}
    }


    describe('deploy', () => {
        it('shall deploy', async () => {
            const [owner] = await ethers.getSigners();
            let {killswitch} = await networkHelpers.loadFixture(deployContracts);
            expect(await killswitch.owner()).to.equal(owner.address);
            expect(await killswitch.engaged()).to.equal(false);
            expect(await killswitch.releaseThreshold()).to.equal(2);
            expect(await killswitch.needReleases()).to.equal(0);
        })
    })


    describe('access control', () => {
        it('only owner shall be able to do this', async () => {
            const [owner, somebody] = await ethers.getSigners();
            let {killswitch} = await networkHelpers.loadFixture(deployContracts);
            let asSomebody = killswitch.connect(somebody);
            await expect(asSomebody.setScram(somebody, true)).to.be.revertedWithCustomError(killswitch, "OwnableUnauthorizedAccount");
            await expect(asSomebody.setReleaser(somebody, true)).to.be.revertedWithCustomError(killswitch, "OwnableUnauthorizedAccount");
        })
    });


    describe('setup', () => {
        it('shall set up ', async () => {

            const [owner, scram, release] = await ethers.getSigners();
            let {killswitch} = await networkHelpers.loadFixture(deployContracts);

            // shall set scrammer
            await expect(killswitch.setScram(scram, true)).to.not.be.revert(ethers);
            expect(await killswitch.scram(scram)).to.equal(true);
            expect(await killswitch.scram(release)).to.equal(false);

            // shall set releaser
            await expect(killswitch.setReleaser(release, true)).to.not.be.revert(ethers);
            expect(await killswitch.releaser(release)).to.equal(true);
            expect(await killswitch.releaser(scram)).to.equal(false);

            //  shall not allow releaser to be the scramer
            await expect(killswitch.setScram(release, true)).to.be.revertedWith('Killswitch: releaser cannot be scramer');
            await expect(killswitch.setReleaser(scram, true)).to.be.revertedWith('Killswitch: releaser cannot be scramer');
        })
    })


    describe('operations', () => {

        async function configUsers() {
            const [owner, scram, release1, release2] = await ethers.getSigners();
            let {killswitch} = await deployContracts();
            await killswitch.setReleaser(release1, true);
            await killswitch.setReleaser(release2, true);
            await killswitch.setScram(scram, true);

            return {killswitch};
        }

        it('shall not engage if not authorised', async () => {
            const [owner, scram, release1, release2] = await ethers.getSigners();
            let {killswitch} = await networkHelpers.loadFixture(configUsers);

            await expect(killswitch.engage()).to.be.revertedWith('Killswitch: not scram');

        })
        it('shall engage killswith', async () => {
            const [owner, scram, release1, release2] = await ethers.getSigners();
            let {killswitch} = await networkHelpers.loadFixture(configUsers);

            await expect(killswitch.connect(scram).engage()).to.emit(killswitch, "Engaged").withArgs(scram);
            expect(await killswitch.engaged()).to.equal(true);
            expect(await killswitch.needReleases()).to.equal(2);
        })


        it('shall  take 2 users to release', async () => {

            const [owner, scram, release1, release2 , somebody] = await ethers.getSigners();
            let {killswitch} = await networkHelpers.loadFixture(configUsers);

            await expect(killswitch.connect(scram).engage()).to.emit(killswitch, "Engaged");

            // shall not allow  unathorised rteleaser
            await expect(killswitch.connect(somebody).release()).to.be.revertedWith('Killswitch: not releaser');

            //  first release,  successful but not enough
            await expect(killswitch.connect(release2).release()).to.emit(killswitch, "Released").withArgs(release2, false);
            expect(await killswitch.engaged()).to.equal(true);
            expect(await killswitch.needReleases()).to.equal(1);

            //  shall not allow releaser to release again
            await expect(killswitch.connect(release2).release()).to.be.revertedWith('Killswitch: already released');

            //  shall release with another user
            await expect(killswitch.connect(release1).release()).to.emit(killswitch, "Released").withArgs(release1, true);
            expect(await killswitch.engaged()).to.equal(false);
            expect(await killswitch.needReleases()).to.equal(0);


            //  shall be operatove again
            await expect(killswitch.connect(scram).engage()).to.emit(killswitch, "Engaged").withArgs(scram);
            expect(await killswitch.engaged()).to.equal(true);
            expect(await killswitch.needReleases()).to.equal(2);

            await expect(killswitch.connect(release1).release()).to.emit(killswitch, "Released").withArgs(release1, false);
            await expect(killswitch.connect(release2).release()).to.emit(killswitch, "Released").withArgs(release2, true);
            expect(await killswitch.engaged()).to.equal(false);
            expect(await killswitch.needReleases()).to.equal(0);

        })
    })
})
