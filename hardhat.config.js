import "@nomicfoundation/hardhat-viem";
import "@nomicfoundation/hardhat-verify";
import dotenv from "dotenv";

dotenv.config();

/** @type import('hardhat/config').HardhatUserConfig */
export default {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    ethereum: {
      type: "http",
      url: `https://eth-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
      accounts: process.env.BSC_PRIVATE_KEY ? [process.env.BSC_PRIVATE_KEY] : [],
      chainId: 1,
    },
    bsc: {
      type: "http",
      url: "https://bsc-dataseed1.binance.org",
      accounts: process.env.BSC_PRIVATE_KEY ? [process.env.BSC_PRIVATE_KEY] : [],
      chainId: 56,
    },
  },
  etherscan: {
    apiKey: {
      ethereum: process.env.ALCHEMY_API_KEY || "",
      bsc: process.env.BSCSCAN_API_KEY || "",
    },
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  mocha: {
    timeout: 40000,
  },
};
