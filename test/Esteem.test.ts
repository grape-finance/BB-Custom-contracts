import { expect } from "chai";
import { network } from "hardhat";

const { ethers } = await network.connect();


describe("Esteem.sol", () => {


    it("Should be able to create contract", async () => {
        const esteem = await ethers.deployContract("Esteem");
        expect(await esteem.name()).to.equal("Esteem Token");
    })
})
