import {expect} from "chai";
import {network} from "hardhat";
import {ZeroAddress} from "ethers";

const {ethers} = await network.connect();


describe("Zapper.sol", () => {

    async function deployContracts() {
        const [deployer, owner] = await ethers.getSigners();
        const zapperInstance = await ethers.deployContract("LPZapper", [owner, '0xA1077a294dDE1B09bB078844df40758a5D0f9a27', '0x165C3410fC91EF562C50559f7d2289fEbed552d9']);
        let zapper = zapperInstance.connect(owner);
        return {zapper};
    }

    describe(' deployment', () => {

        it("Should be able to create contract", async () => {
            const [deployer, owner] = await ethers.getSigners();
            let {zapper} = await deployContracts();

            await expect(await zapper.router()).to.be.equal('0x165C3410fC91EF562C50559f7d2289fEbed552d9');

        })
    })

    describe('access control', () => {

        it("only owner methods", async () => {
            const [deployer, owner, somebody] = await ethers.getSigners();
            let {zapper} = await deployContracts();
            //Revert function because user is not the owner
            await expect(zapper.connect(somebody).addDustToken(somebody)).to.be.revertedWithCustomError(zapper, "OwnableUnauthorizedAccount");
            await expect(zapper.connect(somebody).removeDustToken(somebody)).to.be.revertedWithCustomError(zapper, "OwnableUnauthorizedAccount");
            await expect(zapper.connect(somebody).addFavor(somebody, somebody, somebody)).to.be.revertedWithCustomError(zapper, "OwnableUnauthorizedAccount");
            await expect(zapper.connect(somebody).adminWithdraw(somebody, somebody, 1n)).to.be.revertedWithCustomError(zapper, "OwnableUnauthorizedAccount");
            await expect(zapper.connect(somebody).adminWithdrawPLS(somebody, 1n)).to.be.revertedWithCustomError(zapper, "OwnableUnauthorizedAccount");
            await expect(zapper.connect(somebody).removeFavorToken(somebody)).to.be.revertedWithCustomError(zapper, "OwnableUnauthorizedAccount");
            await expect(zapper.connect(somebody).setPool(somebody)).to.be.revertedWithCustomError(zapper, "OwnableUnauthorizedAccount");

        })

    })

    describe('token managements', () => {

        it('manage dust tokens', async () => {
            const [deployer, owner, somebody] = await ethers.getSigners();
            let {zapper} = await deployContracts();
            //Add dust token
            await expect(zapper.addDustToken(somebody)).to.not.be.revert(ethers);
            expect(await zapper.isDustToken(somebody)).to.be.equal(true);

            await expect(zapper.removeDustToken(somebody)).to.not.be.revert(ethers);
            expect(await zapper.isDustToken(somebody)).to.be.equal(false);

        })

        it("mabage favor tokens", async () => {
            const [deployer, owner, favor, lp, base] = await ethers.getSigners();
            let {zapper} = await deployContracts();

            // add favor token to favor
            expect(await zapper.addFavor(favor, lp, base)).to.not.be.revert(ethers);

            // shall have set up mappings
            expect(await zapper.tokenToFavor(base)).to.be.equal(favor);
            expect(await zapper.favorToLp(favor)).to.be.equal(lp);
            expect(await zapper.favorToToken(favor)).to.be.equal(base);

            //  shall remove favor mapping
            expect(await zapper.removeFavorToken(favor)).to.not.be.revert(ethers);

            // shall have removed mappings
            expect(await zapper.tokenToFavor(base)).to.be.equal(ZeroAddress);
            expect(await zapper.favorToLp(favor)).to.be.equal(ZeroAddress);
            expect(await zapper.favorToToken(favor)).to.be.equal(ZeroAddress);

        })

    })


})
