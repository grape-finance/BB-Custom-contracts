import { expect } from "chai";
import { network } from "hardhat";

const { ethers } = await network.connect();


describe("Zapper.sol", () => {

    async function deployContracts() {
        const [deployer, owner] = await ethers.getSigners();
        const zapperInstance = await ethers.deployContract("LPZapper", [owner, '0xA1077a294dDE1B09bB078844df40758a5D0f9a27', '0x165C3410fC91EF562C50559f7d2289fEbed552d9']);
        let zapper = zapperInstance.connect(owner);
        return { zapper };
    }

    describe(' deployment', () => {

        it("Should be able to create contract", async () => {
            const [deployer, owner] = await ethers.getSigners();
            let { zapper } = await deployContracts();

            await expect(await zapper.router()).to.be.equal('0x165C3410fC91EF562C50559f7d2289fEbed552d9');


        })
    })

    describe('access control', () => {

        it("only owner methods", async () => {
            const [deployer, owner, somebody] = await ethers.getSigners();
            let { zapper } = await deployContracts();
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

    describe('adding tokens', () => {

        it("add tokens", async () => {
            const [deployer, owner, somebody] = await ethers.getSigners();
            let { zapper } = await deployContracts();
            //Add dust token
            expect(await zapper.addDustToken(somebody)).to.be.not.revert;
            expect(await zapper.isDustToken(somebody)).to.be.equal(true);

            //add token to favor
            expect(await zapper.addFavor(somebody, deployer, owner)).to.be.not.revert;
            expect(await zapper.tokenToFavor(somebody)).to.be.equal(deployer);

            //add favor to lp

            expect(await zapper.favorToLp(somebody)).to.be.equal(deployer);

            //add favor to lp

            expect(await zapper.favorToToken(somebody)).to.be.equal(deployer);

        })

        it("remove tokens", async () => {
            const [deployer, owner, somebody] = await ethers.getSigners();
            let { zapper } = await deployContracts();
            //Add dust token
            expect(await zapper.addDustToken(somebody)).to.be.not.revert;
            expect(await zapper.isDustToken(somebody)).to.be.equal(true);
            // remove dust token
            expect(await zapper.removeDustToken(somebody)).to.be.not.revert;
            expect(await zapper.isDustToken(somebody)).to.be.equal(false);

        expect(await zapper.addFavor(somebody, deployer, owner)).to.be.not.revert;


            expect(await zapper.tokenToFavor(deployer)).to.be.equal(somebody);


            expect(await zapper.favorToLp(somebody)).to.be.equal(deployer);

            expect(await zapper.favorToToken(somebody)).to.be.equal(deployer);

            //remove flavor token
            expect(await zapper.removeFavorToken(somebody)).to.be.not.revert;
            expect(await zapper.tokenToFavor(somebody)).to.be.equal('0x0000000000000000000000000000000000000000');
            expect(await zapper.favorToLp(somebody)).to.be.equal('0x0000000000000000000000000000000000000000');
            expect(await zapper.favorToToken(somebody)).to.be.equal('0x0000000000000000000000000000000000000000');



        })



    })


})
