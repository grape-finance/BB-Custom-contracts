import {expect} from "chai";
import {network} from "hardhat";

const {ethers} = await network.connect();


describe("Esteem.sol", () => {

    async function deployContracts() {
        const [owner] = await ethers.getSigners();
        const esteem = await ethers.deployContract("Esteem", [owner]);

        return {esteem};
    }

    describe(' deployment', () => {

        it("Should be able to create contract", async () => {
            const [owner] = await ethers.getSigners();
            let {esteem} = await deployContracts();

            expect(await esteem.name()).to.equal("Esteem Token");
            expect(await esteem.symbol()).to.equal("ESTEEM");
            expect(await esteem.owner()).to.equal(owner.address);
        })
    })

    describe('access control', () => {

        it("only owner methods", async () => {
            const [owner, somebody] = await ethers.getSigners();
            let {esteem} = await deployContracts();

            await expect(esteem.connect(somebody).addMinter(somebody)).to.be.revertedWithCustomError(esteem, "OwnableUnauthorizedAccount");
            await expect(esteem.connect(somebody).removeMinter(somebody)).to.be.revertedWithCustomError(esteem, "OwnableUnauthorizedAccount");
        })


        it("only minter methods", async () => {
            const [owner, somebody] = await ethers.getSigners();
            let {esteem} = await deployContracts();
            await expect(esteem.connect(somebody).mint(somebody, 123n)).to.be.revertedWith('OnlyMinter: caller is not a minter');

        })
    })

    describe('mint', () => {
        it("shall mint esteem, set and reset minters", async () => {
            const [owner, minter, receiver] = await ethers.getSigners();
            let {esteem} = await deployContracts();

            // shall set  minter up
            await expect(esteem.addMinter(minter)).to.emit(esteem, "MinterAdded").withArgs(minter.address);

            // shall mint and transfer
            await expect(esteem.connect(minter).mint(receiver, 239n)).to.not.be.revert(ethers);
            expect(await esteem.balanceOf(receiver)).to.equal(239n);


            //  shall remove minter
            expect(esteem.removeMinter(minter)).to.emit(esteem, "MinterRemoved").withArgs(minter.address);

            //  shall not mint under this address anumore
            await expect(esteem.connect(minter).mint(receiver, 123n)).to.be.revertedWith('OnlyMinter: caller is not a minter');

        })

    })
})
