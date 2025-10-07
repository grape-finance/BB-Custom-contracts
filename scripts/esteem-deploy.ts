// Deploy and config Esteem.sol
import {network} from "hardhat";
import { Contract } from "ethers";

/** Constructor args */
const OWNER  = "0x5e9E3457433b4B767e458ABecaf4128eeb3DCc97";

async function verify(address: string, args: any[]) {
  console.log(`\n To verify contract, run:`);
  console.log(`npx hardhat verify --network pulse ${address} "${args[0]}"`);
}

async function main() {
  const {ethers} = await network.connect();
  const [signer] = await ethers.getSigners();
  const amountMint = ethers.parseUnits("220000", 18);

  console.log("Deployer:", signer.address);

  const Factory = await ethers.getContractFactory("contracts/Esteem.sol:Esteem");
  const esteem = await Factory.deploy(OWNER);
  await esteem.waitForDeployment();
  let esteemAddr = await esteem.getAddress();
  console.log("✓ Deployed Esteem at:", esteemAddr);

  const ABI = (await ethers.getContractFactory("contracts/Esteem.sol:Esteem")).interface;
  const CA: Contract = new ethers.Contract(esteemAddr, ABI, signer);

  console.log(`Set Minter`);
  await (await CA.addMinter(signer.address)).wait();
  console.log(`Set Minter -> ${signer.address}`);

  console.log(`Minting`);
  await (await CA.mint(signer.address, amountMint)).wait();
  console.log(`Minted to -> ${signer.address}`);
  
  // Verify cli output
  await verify(esteemAddr, [OWNER]);

  console.log("\n✅ Deployment + configuration complete.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
