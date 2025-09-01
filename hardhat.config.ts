import type { HardhatUserConfig } from "hardhat/config";

import hardhatToolboxMochaEthersPlugin from "@nomicfoundation/hardhat-toolbox-mocha-ethers";
import { configVariable } from "hardhat/config";

const config: HardhatUserConfig = {
  plugins: [hardhatToolboxMochaEthersPlugin],
  solidity: {
      compilers: [
      {
        version: "0.8.20",   // your main version
              settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
        
      },
      {
        version: "0.5.16",    // older contracts
        settings: {},
      },
      {
        version: "0.6.6",   // for example, Uniswap V2
        settings: {},
      },
    ],
  
    // profiles: {
    //   default: {
    //     version: "0.8.28",  
        
    //   },
    //   production: {
    //     version: "0.8.28",
    //     settings: {
    //       optimizer: {
    //         enabled: true,
    //         runs: 200,
    //       },
    //     },
    //   },
    // },
  },
  networks: {
    hardhatMainnet: {
      type: "edr-simulated",
      chainType: "l1",
    },
    hardhatOp: {
      type: "edr-simulated",
      chainType: "op",
    },
    sepolia: {
      type: "http",
      chainType: "l1",
      url: configVariable("SEPOLIA_RPC_URL"),
      accounts: [configVariable("SEPOLIA_PRIVATE_KEY")],
    },
  },
};

export default config;
