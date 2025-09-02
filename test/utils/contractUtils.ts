import unsiswapV2Factory from "@uniswap/v2-core/build/UniswapV2Factory.json";
import uniswapV2Router from "@uniswap/v2-periphery/build/UniswapV2Router02.json";

//  create  uniswap V2 factory fee reciever is set to owner
import {HardhatEthersSigner} from "@nomicfoundation/hardhat-ethers/types";
import {network} from "hardhat";
import {IERC20, IUniswapV2Factory} from "../../types/ethers-contracts/index.js";

const {ethers} = await network.connect();


async function createUSV2Factory(owner: HardhatEthersSigner) {

    let uniswapFactpry = new ethers.ContractFactory(unsiswapV2Factory.interface, unsiswapV2Factory.bytecode, owner);
    let factory = await uniswapFactpry.connect(owner).deploy(owner.address);

    await factory.waitForDeployment();
    return await ethers.getContractAt(unsiswapV2Factory.interface, await factory.getAddress(), owner);
}

//  create  uniswap V2 factory factory  fee reciever is set to ownber
async function createUSV2Router(owner: HardhatEthersSigner, uniswapFactory: IUniswapV2Factory, weth: IERC20) {
    let routerFactory = new ethers.ContractFactory(uniswapV2Router.interface, uniswapV2Router.bytecode, owner);
    let router = await routerFactory.connect(owner).deploy(uniswapFactory, weth);

    await router.waitForDeployment();

    // return typesafe interface
    return await ethers.getContractAt(uniswapV2Router.interface, await router.getAddress(), owner);
}

// reate token and mint 1M for the ownber
async function createToken(owner: HardhatEthersSigner, name: string, symbol: string) {
    let tokenFactory = await ethers.getContractFactory("Token");

    let token = await tokenFactory.connect(owner).deploy(name, symbol, owner);
    await token.mint(1_000_000_000_000_000_000_000_000_000n)
    return token;
}

export {createToken, createUSV2Factory, createUSV2Router}
