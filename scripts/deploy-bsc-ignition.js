import hre from "hardhat";

// Main deployment function
async function main() {
  console.log("🚀 Starting BSC Mainnet Deployment...\n");

  try {
    // Get wallet clients and public client using viem
    const walletClients = await hre.viem.getWalletClients();
    const publicClient = await hre.viem.getPublicClient();
    
    if (!walletClients || walletClients.length === 0) {
      throw new Error("No wallet clients available. Check your BSC_PRIVATE_KEY in .env");
    }

    const deployer = walletClients[0];
    const deployerAddress = deployer.account.address;

    console.log("Deploying with account:", deployerAddress);
    const balance = await publicClient.getBalance({ address: deployerAddress });
    console.log("Account balance:", balance.toString(), "wei\n");

    // Deploy Staking contract
    console.log("1️⃣  Deploying Staking contract...");
    const stakingHash = await deployer.deployContract({
      abi: (await import("../artifacts/contracts/Staking.sol/Staking.json", {
        assert: { type: "json" },
      })).default.abi,
      bytecode: (await import("../artifacts/contracts/Staking.sol/Staking.json", {
        assert: { type: "json" },
      })).default.bytecode,
      args: [deployerAddress],
    });

    const stakingReceipt = await publicClient.waitForTransactionReceipt({ hash: stakingHash });
    console.log("✅ Staking deployed to:", stakingReceipt.contractAddress);

    // Deploy MultiDEXStaking contract
    console.log("\n2️⃣  Deploying MultiDEXStaking contract...");
    const pancakePositionManager = "0x46A15B0b27311cedF172AB29E4f4766fbE7F4364"; // PancakeSwap V3 on BSC
    const uniswapPositionManager = "0x0000000000000000000000000000000000000000"; // Not available on BSC

    const multiDexHash = await deployer.deployContract({
      abi: (await import("../artifacts/contracts/Stakingv3.sol/MultiDEXStaking.json", {
        assert: { type: "json" },
      })).default.abi,
      bytecode: (await import("../artifacts/contracts/Stakingv3.sol/MultiDEXStaking.json", {
        assert: { type: "json" },
      })).default.bytecode,
      args: [pancakePositionManager, uniswapPositionManager, deployerAddress],
    });

    const multiDexReceipt = await publicClient.waitForTransactionReceipt({ hash: multiDexHash });
    console.log("✅ MultiDEXStaking deployed to:", multiDexReceipt.contractAddress);

    console.log("\n=== Deployment Summary ===");
    console.log("Network: BSC Mainnet (Chain ID: 56)");
    console.log("Deployer:", deployerAddress);
    console.log("Staking:", stakingReceipt.contractAddress);
    console.log("MultiDEXStaking:", multiDexReceipt.contractAddress);
  } catch (error) {
    console.error("❌ Deployment failed:", error.message || error);
    process.exit(1);
  }
}

main();

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
