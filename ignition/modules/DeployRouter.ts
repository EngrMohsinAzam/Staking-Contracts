import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const DeployRouterModule = buildModule("DeployRouterModule", (m) => {
  // Get parameters from module parameters
  // BSC Mainnet addresses:
  // - PancakeSwap V3 Factory: 0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865
  // - WBNB (WETH9): 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c
  // - NFT Descriptor: You need to deploy or use an existing descriptor contract address
  
  const deployer = m.getParameter("deployer", "0x2CC238026cD37Ab6102FDdc4a1a9c99b5B1F7655"); // Owner address
  const factory = m.getParameter(
    "factory",
    "0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865" // PancakeSwap V3 Factory (BSC)
  );
  const weth9 = m.getParameter(
    "weth9",
    "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c" // WBNB (BSC)
  );
  const tokenDescriptor = m.getParameter(
    "tokenDescriptor",
    "0x0000000000000000000000000000000000000000" // NFT Descriptor - YOU MUST PROVIDE THIS
  );

  const router = m.contract("NonfungiblePositionManager", [
    deployer,
    factory,
    weth9,
    tokenDescriptor,
  ], {
    id: "NonfungiblePositionManager",
  });

  return { router };
});

export default DeployRouterModule;
