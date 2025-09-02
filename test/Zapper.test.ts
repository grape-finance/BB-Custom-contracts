import {expect} from "chai";
import {network} from "hardhat";
import {ZeroAddress} from "ethers";

const {ethers} = await network.connect();


describe("Zapper.sol", () => {

    async function deployContracts() {
        const [deployer, owner, treasury, esteem] = await ethers.getSigners();
        const zapperInstance = await ethers.deployContract("LPZapper", [owner, '0xA1077a294dDE1B09bB078844df40758a5D0f9a27', '0x165C3410fC91EF562C50559f7d2289fEbed552d9']);
        let zapper = zapperInstance.connect(owner);

        const favorInstance = await ethers.deployContract("FavorPLS", [owner, 123_000_000_000_000_000_000_000_000n, treasury, esteem]);
        let favor = favorInstance.connect(owner);

        await favor.setTaxExempt(zapper, true);

        let weth = await createToken(owner, 'wethweth', "t0");
        let v2factory = await createUSV2Factory(owner);
        let v2router = await createUSV2Router(owner, v2factory, weth);


        // mock pool to test flash loans
        const mockPoolInstance = await ethers.deployContract("MockPool", []);
        let mockPool = mockPoolInstance.connect(owner);


        await zapper.setPool(mockPool);

        return {zapper, favor, mockPool};
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
            await expect(zapper.connect(somebody).setAddressProvider(somebody)).to.be.revertedWithCustomError(zapper, "OwnableUnauthorizedAccount");

        })

        //  msg sender shall be a registered pool only
        it("shall no allow invocation from a wrong pool", async () => {
            const [deployer, owner, somebody] = await ethers.getSigners();
            let {zapper, favor} = await deployContracts();

            await expect(zapper.executeOperation(favor, 0n, 0n, somebody, "0x")).to.be.revertedWith("not registered pool");
        })

        //  if the pool is registered, initiator shall be a contract itself
        //  we trust aave pol that it does the right thing here.
        it("shall no allow invocation from a wrong pool caller", async () => {
            const [deployer, owner, somebody, pool] = await ethers.getSigners();
            let {zapper, favor} = await deployContracts();

            await zapper.setPool(pool);

            await expect(zapper.connect(pool).executeOperation(favor, 0n, 0n, somebody, "0x")).to.be.revertedWith("bad initiator");
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


        it("shall withdraw tokens as admin", async () => {
            const [deployer, owner, receiver] = await ethers.getSigners();
            let {zapper, favor} = await deployContracts();

            await favor.transfer(zapper, 1000n);

            expect(await favor.balanceOf(zapper)).to.equal(1000n);
            await zapper.adminWithdraw(favor, receiver, 1000n);

            expect(await favor.balanceOf(zapper)).to.equal(0n);
            expect(await favor.balanceOf(receiver)).to.equal(1000n);

        })

    })

    describe('zapping operation', () => {
        it('shall request flash loan properly', async () => {
            const [deployer, owner] = await ethers.getSigners();
            let {zapper, favor, mockPool} = await deployContracts();

            await expect(zapper.requestFlashLoan(12345n, favor)).to.not.be.revert(ethers);

        })
    })
})
