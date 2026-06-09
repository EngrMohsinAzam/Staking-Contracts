import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const DeployStakingModule = buildModule("DeployStakingModule", (m) => {
  // Get the initial owner address from the module parameters
  // You can pass this when deploying: --parameters '{"DeployStakingModule":{"initialOwner":"0x..."}}'
  const initialOwner = m.getParameter("initialOwner", m.getAccount(0));

  const staking = m.contract("Staking", [initialOwner], {
    id: "Staking",
  });

  return { staking };
});

export default DeployStakingModule;
