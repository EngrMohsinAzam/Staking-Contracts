import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const DeployTokenModule = buildModule("DeployTokenModule", (m) => {
  // Get parameters from module parameters
  // You can pass these when deploying: --parameters '{"DeployTokenModule":{"tokenName":"My Token","tokenSymbol":"MTK",...}}'
  const tokenName = m.getParameter("tokenName", "My Token");
  const tokenSymbol = m.getParameter("tokenSymbol", "MTK");
  const decimals = m.getParameter("decimals", 18);
  const supply = m.getParameter("supply", 1000000); // Will be multiplied by 10^decimals
  const txFee = m.getParameter("txFee", 100); // 1% in basis points
  const burnFee = m.getParameter("burnFee", 50); // 0.5% in basis points
  const feeAddress = m.getParameter("feeAddress", "0x2CC238026cD37Ab6102FDdc4a1a9c99b5B1F7655"); // Owner address
  const tokenOwner = m.getParameter("tokenOwner", "0x2CC238026cD37Ab6102FDdc4a1a9c99b5B1F7655"); // Owner address
  const service = m.getParameter("service", "0x0000000000000000000000000000000000000000"); // Service address for payment

  const token = m.contract(
    "AdvancedERC20Token",
    [
      tokenName,
      tokenSymbol,
      decimals,
      supply,
      txFee,
      burnFee,
      feeAddress,
      tokenOwner,
      service,
    ],
    {
      id: "AdvancedERC20Token",
      value: 0, // Can be set if payment to service is needed
    }
  );

  return { token };
});

export default DeployTokenModule;
