import { expect } from "chai";
import { network } from "hardhat";

const { ethers } = await network.connect();


describe("Zapper.sol", () => {


    it("Should be able to create contract", async () => {
        const esteem = await ethers.deployContract("LPZapper");
        expect(await esteem.name()).to.equal("Esteem Token");
    })
})
