import { ethers } from "ethers";
import { readFileSync } from "fs";

async function main() {
  console.log("🚀 Deploying to BSC Mainnet...\n");

  // Get private key from environment
  const privateKey = process.env.BSC_PRIVATE_KEY;
  if (!privateKey) {
    throw new Error("BSC_PRIVATE_KEY not found in .env file");
  }

  // Create provider and signer
  const provider = new ethers.JsonRpcProvider("https://bsc-dataseed1.binance.org");
  const signer = new ethers.Wallet(privateKey, provider);

  console.log("Deploying with account:", signer.address);

  // Get balance
  const balance = await provider.getBalance(signer.address);
  console.log("Account balance:", ethers.formatEther(balance), "BNB\n");

  // Read contract ABIs and bytecode
  const stakingArtifact = JSON.parse(readFileSync("./artifacts/contracts/Staking.sol/Staking.json", "utf-8"));
  const multiDEXArtifact = JSON.parse(readFileSync("./artifacts/contracts/Stakingv3.sol/MultiDEXStaking.json", "utf-8"));

  // Deploy Staking contract
  console.log("1️⃣  Deploying Staking contract...");
  const stakingFactory = new ethers.ContractFactory(stakingArtifact.abi, stakingArtifact.bytecode, signer);
  const staking = await stakingFactory.deploy(signer.address);
  await staking.waitForDeployment();
  const stakingAddress = await staking.getAddress();
  console.log("✅ Staking deployed to:", stakingAddress);

  // Deploy MultiDEXStaking contract
  console.log("\n2️⃣  Deploying MultiDEXStaking contract...");
  const PANCAKE_POSITION_MANAGER = process.env.BSC_PANCAKE_POSITION_MANAGER || "0x46A15B0b27311cedF172AB29E4f4766fbE7F4364";
  const UNISWAP_POSITION_MANAGER = process.env.BSC_UNISWAP_POSITION_MANAGER || "0x0000000000000000000000000000000000000000";

  console.log("PancakeSwap Position Manager:", PANCAKE_POSITION_MANAGER);
  console.log("Uniswap Position Manager:", UNISWAP_POSITION_MANAGER);

  const multiDexFactory = new ethers.ContractFactory(multiDEXArtifact.abi, multiDEXArtifact.bytecode, signer);
  const multiDexStaking = await multiDexFactory.deploy(
    PANCAKE_POSITION_MANAGER,
    UNISWAP_POSITION_MANAGER,
    signer.address
  );
  await multiDexStaking.waitForDeployment();
  const multiDexAddress = await multiDexStaking.getAddress();
  console.log("✅ MultiDEXStaking deployed to:", multiDexAddress);

  console.log("\n=== Deployment Summary ===");
  console.log("Network: BSC Mainnet (Chain ID: 56)");
  console.log("Deployer:", signer.address);
  console.log("Staking Contract:", stakingAddress);
  console.log("MultiDEXStaking Contract:", multiDexAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:", error.message);
    process.exit(1);
  });
