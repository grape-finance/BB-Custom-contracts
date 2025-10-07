import "@nomicfoundation/hardhat-verify";
import type { HardhatUserConfig } from "hardhat/config";
import hardhatNetworkHelpersPlugin from "@nomicfoundation/hardhat-network-helpers";
import hardhatToolboxMochaEthersPlugin from "@nomicfoundation/hardhat-toolbox-mocha-ethers";
import {configVariable} from "hardhat/config";
import * as dotenv from "dotenv";

dotenv.config();

const config: HardhatUserConfig = {
    plugins: [hardhatToolboxMochaEthersPlugin, hardhatNetworkHelpersPlugin],
    solidity: {
        compilers: [
            {
                version: "0.8.20",   // main version
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 1000,
                    },
                },
            },
            {
                version: "0.5.16",    // older contracts
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 1000,
                    },
                },
            },
            {
                version: "0.6.6",   // Older contracts for example, Uniswap V2
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 1000,
                    },
                },
            },
        ],
  },
  networks: {
    hardhatMainnet: {
      loggingEnabled: true,
      type: "edr-simulated",
      chainType: "l1",
    },
    hardhatOp: {
      loggingEnabled: true,
      type: "edr-simulated",
      chainType: "op",
    },
    sepolia: {
      type: "http",
      chainType: "l1",
      url: configVariable("SEPOLIA_RPC_URL"),
      accounts: [configVariable("SEPOLIA_PRIVATE_KEY")],
    },

    pulse: {
      type: "http",
      chainType: "l1",
      url: configVariable("PULSECHAIN_RPC_URL"),         
      accounts: [configVariable("PULSECHAIN_PRIVATE_KEY")],
      chainId: 369,
    },


    pulsetest: {
      type: "http",
      chainType: "l1",
      url: configVariable("PULSECHAIN_TESTNET_RPC_URL"),  
      accounts: [configVariable("PULSECHAIN_PRIVATE_KEY")],
      chainId: 940,
    },
  },

verify: {},
  chainDescriptors: {
    369: {
      name: "PulseChain",
      blockExplorers: {
        blockscout: {
          name: "PulseScan",
          url: "https://scan.pulsechain.com",
          apiUrl: "https://api.scan.pulsechain.com/api",
        },
      },
    },
    943: {
      name: "PulseChain Testnet v4",
      blockExplorers: {
        blockscout: {
          name: "PulseScan Testnet",
          url: "https://scan.v4.testnet.pulsechain.com",
          apiUrl: "https://api.scan.v4.testnet.pulsechain.com/api",
        },
      },
    },
  },
};

export default config;
