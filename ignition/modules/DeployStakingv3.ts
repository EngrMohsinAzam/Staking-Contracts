import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const DeployStakingv3Module = buildModule("DeployStakingv3Module", (m) => {
  // Get parameters from module parameters
  // BSC Mainnet: PancakeSwap V3 Position Manager - 0x46A15B0b27311ceDF172AB29E4f4766fbE7F4364
  // Ethereum Mainnet: Uniswap V3 Position Manager - 0xC36442b4a4522E871399CD717aBDD847Ab11FE88
  // Note: Use PancakeSwap address for BSC deployment, Uniswap address for Ethereum deployment
  const pancakePositionManager = m.getParameter(
    "pancakePositionManager",
    "0x46A15B0b27311ceDF172AB29E4f4766fbE7F4364" // PancakeSwap V3 Position Manager (BSC)
  );
  const uniswapPositionManager = m.getParameter(
    "uniswapPositionManager",
    "0xC36442b4a4522E871399CD717aBDD847Ab11FE88" // Uniswap V3 Position Manager (Ethereum)
  );
  const initialOwner = m.getParameter(
    "initialOwner",
    "0x2CC238026cD37Ab6102FDdc4a1a9c99b5B1F7655"
  );

  const stakingv3 = m.contract("MultiDEXStaking", [
    pancakePositionManager,
    uniswapPositionManager,
    initialOwner,
  ], {
    id: "MultiDEXStaking",
  });

  return { stakingv3 };
});

export default DeployStakingv3Module;
