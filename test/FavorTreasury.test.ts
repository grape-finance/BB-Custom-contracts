import {expect} from "chai";
import {network} from "hardhat";
import {ZeroAddress} from "ethers";
import {createToken, createUSV2Factory, createUSV2Router} from "./utils/contractUtils.js";

const {ethers} = await network.connect();


describe('FavorTreasury.sol', () => {

    async function deployContracts() {

        const [deployer, owner] = await ethers.getSigners();

        const favorTreasuryInstance = await ethers.deployContract("FavorTreasury", [owner]);
        let favorTreasury = favorTreasuryInstance.connect(owner);

        return {favorTreasury};
    }

    describe('deployment', () => {

        it("shall be able to deploy", async () => {
            const [deployer, owner] = await ethers.getSigners();
            let {favorTreasury} = await deployContracts();

            expect(favorTreasury).to.not.equal(null);
            expect(await favorTreasury.owner()).to.equal(owner.address);
        })
    })
})