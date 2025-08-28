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
})