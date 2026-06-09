import { ethers } from "ethers";
import { readFileSync } from "fs";
import dotenv from "dotenv";

dotenv.config();

async function main() {
  console.log("🚀 Deploying Token and Router to BSC Mainnet...\n");

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

  // Owner address
  const OWNER_ADDRESS = "0x2CC238026cD37Ab6102FDdc4a1a9c99b5B1F7655";

  // Deploy Token contract
  console.log("1️⃣  Deploying AdvancedERC20Token contract...");
  const tokenArtifact = JSON.parse(readFileSync("./artifacts/contracts/token.sol/AdvancedERC20Token.json", "utf-8"));
  const tokenFactory = new ethers.ContractFactory(tokenArtifact.abi, tokenArtifact.bytecode, signer);
  const token = await tokenFactory.deploy(
    "My Token",           // _name
    "MTK",               // _symbol
    18,                  // _decimals
    1000000,             // _supply (will be 1,000,000 * 10^18)
    100,                 // _txFee (1%)
    50,                  // _burnFee (0.5%)
    OWNER_ADDRESS,       // _FeeAddress
    OWNER_ADDRESS,       // tokenOwner
    "0x0000000000000000000000000000000000000000" // service
  );
  await token.waitForDeployment();
  const tokenAddress = await token.getAddress();
  console.log("✅ AdvancedERC20Token deployed to:", tokenAddress);

  // Deploy Router contract
  console.log("\n2️⃣  Deploying NonfungiblePositionManager contract...");
  const PANCAKE_FACTORY = "0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865"; // PancakeSwap V3 Factory (BSC)
  const WBNB = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c"; // WBNB (BSC)
  const TOKEN_DESCRIPTOR = process.env.BSC_TOKEN_DESCRIPTOR || "0x0000000000000000000000000000000000000000"; // NFT Descriptor

  console.log("Factory:", PANCAKE_FACTORY);
  console.log("WBNB:", WBNB);
  console.log("Token Descriptor:", TOKEN_DESCRIPTOR);
  console.log("Deployer:", OWNER_ADDRESS);

  const routerArtifact = JSON.parse(readFileSync("./artifacts/contracts/routerv3.sol/NonfungiblePositionManager.json", "utf-8"));
  const routerFactory = new ethers.ContractFactory(routerArtifact.abi, routerArtifact.bytecode, signer);
  const router = await routerFactory.deploy(
    OWNER_ADDRESS,       // _deployer
    PANCAKE_FACTORY,    // _factory
    WBNB,               // _WETH9
    TOKEN_DESCRIPTOR    // _tokenDescriptor
  );
  await router.waitForDeployment();
  const routerAddress = await router.getAddress();
  console.log("✅ NonfungiblePositionManager deployed to:", routerAddress);

  console.log("\n=== Deployment Summary ===");
  console.log("Network: BSC Mainnet (Chain ID: 56)");
  console.log("Deployer:", signer.address);
  console.log("Owner Address:", OWNER_ADDRESS);
  console.log("Token Contract:", tokenAddress);
  console.log("Router Contract:", routerAddress);
  console.log("\n💡 Save these addresses for future reference!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:", error.message);
    process.exit(1);
  });
