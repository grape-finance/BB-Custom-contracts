import {expect} from "chai";
import {network} from "hardhat";

const {ethers} = await network.connect();


describe("Esteem.sol", () => {

    async function deployContracts() {
        const [owner] = await ethers.getSigners();
        const esteem = await ethers.deployContract("Esteem");

        return {esteem};
    }

    describe(' deployment', () => {

        it("Should be able to create contract", async () => {
            let {esteem} = await deployContracts();


            expect(await esteem.name()).to.equal("Esteem Token");
        })
    })


})
