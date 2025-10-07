// Deploy and config LPZapper.sol
import {network} from "hardhat";
import { Contract } from "ethers";

/** Constructor args */
const OWNER  = "0x5e9E3457433b4B767e458ABecaf4128eeb3DCc97";
const ROUTER = "0x165C3410fC91EF562C50559f7d2289fEbed552d9";
const WPLS   = "0xA1077a294dDE1B09bB078844df40758a5D0f9a27";
const KILL   = "0x9aaE63Ad5a2D8fAaa41102Eb013AFEF8755e4844";

/** Post-deploy params */
const POOL = "0xdB2c92c63e0320511a278673F0dBF8c3ACa7C5Ee";

/** [favor, lp, base] sets adjust for mainnet */
const FAVOR_SETS: [string, string, string][] = [
  ["0x30be72a397667FDfD641E3e5Bd68Db657711EB20","0xdca85EFDCe177b24DE8B17811cEC007FE5098586","0xA1077a294dDE1B09bB078844df40758a5D0f9a27"],
  ["0x47c3038ad52E06B9B4aCa6D672FF9fF39b126806","0x24264d580711474526e8f2a8ccb184f6438bb95c","0x95B303987A60C71504D99Aa1b13B4DA07b0790ab"],
  ["0x545C86cB5aC93E56FFfF9dE27b787B6bf8Ad9E73","0x94220A7B256E6bAe82b76dCab4100Bb735d5547E","0x318B8F738dDA4f7EeC09c43712B3D7127B9D6Fbe"],
];

async function verify(address: string, args: any[]) {
  console.log(`\n To verify contract, run:`);
  console.log(`npx hardhat verify --network pulse ${address} "${args[0]}" "${args[1]}" "${args[2]}" "${args[3]}"`);
}

async function send(label: string, p: Promise<any>) {
  const tx = await p;
  console.log(`  • ${label} tx: ${tx.hash}`);
  await tx.wait(1);
}

async function main() {
  const {ethers} = await network.connect();
  const [signer] = await ethers.getSigners();
  console.log("Deployer:", signer.address);

  const Factory = await ethers.getContractFactory("contracts/LPZapper.sol:LPZapper");
  const zapper = await Factory.deploy(OWNER, ROUTER, WPLS, KILL);
  await zapper.waitForDeployment();
  let zapperAddr = await zapper.getAddress();
  console.log("✓ Deployed LPZapper at:", zapperAddr);

  // 2) Post-deploy config
  const LPZAPPER_ABI = (await ethers.getContractFactory("contracts/LPZapper.sol:LPZapper")).interface;
  const zapperCA: Contract = new ethers.Contract(zapperAddr, LPZAPPER_ABI, signer);

  // Add POOL
  const currentPool: string = await zapperCA.POOL();
  if (currentPool.toLowerCase() !== POOL.toLowerCase()) {
    console.log(`Setting POOL -> ${POOL} (was ${currentPool})`);
    await send("setPool", zapperCA.setPool(POOL));
  } else {
    console.log("POOL already set — skipping");
  }
/*
  // Add favor sets
  const PAIR_ABI = [
    "function token0() view returns (address)",
    "function token1() view returns (address)",
  ];

  for (const [favor, lp, base] of FAVOR_SETS) {
    console.log(`\n→ addFavor: favor=${favor} lp=${lp} base=${base}`);

    const existingLP: string = await zapperCA.favorToLp(favor);
    if (existingLP && existingLP.toLowerCase() !== ZeroAddress.toLowerCase()) {
      console.log(`  • favor already registered → ${existingLP} (skip)`);
      continue;
    }
    const existingFavorForBase: string = await zapperCA.tokenToFavor(base);
    if (existingFavorForBase && existingFavorForBase.toLowerCase() !== ZeroAddress.toLowerCase()) {
      console.log(`  • base already mapped to favor ${existingFavorForBase} (skip)`);
      continue;
    }

    const pair = new ethers.Contract(lp, PAIR_ABI, signer);
    const t0 = (await pair.token0()).toLowerCase();
    const t1 = (await pair.token1()).toLowerCase();
    if (!([t0, t1].includes(favor.toLowerCase()) && [t0, t1].includes(base.toLowerCase()))) {
      throw new Error(`LP mismatch: pair(${t0}, ${t1}) doesn't contain both favor & base`);
    }

    await send("addFavor", zapperCA.addFavor(favor, lp, base));
    console.log("  ✓ added");
  }*/

  // Verify cli output
  await verify(zapperAddr, [OWNER, ROUTER, WPLS, KILL]);

  console.log("\n✅ Deployment + configuration complete.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
