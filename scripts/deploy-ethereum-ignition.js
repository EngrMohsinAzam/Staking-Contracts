import hre from "hardhat";

// Main deployment function
async function main() {
  console.log("🚀 Starting Ethereum Mainnet Deployment...\n");

  // Verify accounts are available
  const accounts = await hre.ethers.getSigners?.() || [];
  if (accounts.length === 0) {
    throw new Error("No accounts available. Check your BSC_PRIVATE_KEY in .env");
  }

  const deployer = accounts[0];
  console.log("Deploying with account:", deployer.address);
  console.log("Network:", (await hre.ethers.provider?.getNetwork?.())?.name || "ethereum");

  // Deploy Staking contract
  console.log("\n1️⃣  Deploying Staking contract...");
  const StakingFactory = await hre.ethers.getContractFactory("Staking");
  const staking = await StakingFactory.deploy(deployer.address);
  await staking.deploymentTransaction()?.wait?.();
  console.log("✅ Staking deployed to:", staking.address || staking.target);

  // Deploy MultiDEXStaking contract
  console.log("\n2️⃣  Deploying MultiDEXStaking contract...");
  const pancakePositionManager = "0x0000000000000000000000000000000000000000"; // Not available on Ethereum
  const uniswapPositionManager = "0xC36442b4a4522E871399CD717aBDD847Ab11FE88"; // Uniswap V3 on Ethereum

  const MultiDEXStakingFactory = await hre.ethers.getContractFactory("MultiDEXStaking");
  const multiDexStaking = await MultiDEXStakingFactory.deploy(
    pancakePositionManager,
    uniswapPositionManager,
    deployer.address
  );
  await multiDexStaking.deploymentTransaction()?.wait?.();
  console.log("✅ MultiDEXStaking deployed to:", multiDexStaking.address || multiDexStaking.target);

  console.log("\n=== Deployment Summary ===");
  console.log("Network: Ethereum Mainnet (Chain ID: 1)");
  console.log("Deployer:", deployer.address);
  console.log("Staking:", staking.address || staking.target);
  console.log("MultiDEXStaking:", multiDexStaking.address || multiDexStaking.target);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  });
