import {network} from "hardhat";
import { Contract } from "ethers";

/** Constructor args */
const OWNER  = "0x5e9E3457433b4B767e458ABecaf4128eeb3DCc97";

async function verify(address: string, args: any[]) {
  console.log(`\n To verify contract, run:`);
  console.log(`npx hardhat verify --network pulse ${address} "${args[0]}"${args[1]}`);
}

async function main() {
  const {ethers} = await network.connect();
  const [signer] = await ethers.getSigners();

  console.log("Deployer:", signer.address);

  const Factory = await ethers.getContractFactory("contracts/Killswitch.sol:Killswitch");
  const ks = await Factory.deploy(2, OWNER);
  await ks.waitForDeployment();
  let addr = await ks.getAddress();
  console.log("✓ Deployed Killswitch at:", addr);

  const ABI = (await ethers.getContractFactory("contracts/Killswitch.sol:Killswitch")).interface;
  const CA: Contract = new ethers.Contract(addr, ABI, signer);

  console.log(`Set Scrammers`);
  await (await CA.setScram(signer.address, true)).wait();
  await (await CA.setScram('0xc0702Ae0374F83fc3bA71CE2B30A323b09EC19da', true)).wait();
  console.log(`Scrammers set`);

  console.log(`Set Releasers`);
  await (await CA.setReleaser('0x6831f815963FfCe95521271b94164eb4C82e7621', true)).wait();
  await (await CA.setReleaser('0x1EA35487AE62322F61f4C0F639a598d9eEB2F340', true)).wait();
  await (await CA.setReleaser('0xcE04c590344c2bd8e2bfe49A280c1d501dc8c000', true)).wait();
  console.log(`Releasers Set`);
  
  // Verify cli output
  await verify(addr, [2, OWNER]);

  console.log("\n✅ Deployment + configuration complete.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
