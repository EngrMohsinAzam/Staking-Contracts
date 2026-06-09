#!/bin/bash
# Direct deployment commands for BSC Mainnet

echo "🚀 Deploying to BSC Mainnet..."
echo ""
echo "Option 1: Using direct Hardhat deployment"
echo "npx hardhat run scripts/deploy-bsc.js --network bsc"
echo ""
echo "Option 2: Using Ignition CLI (when available)"
echo "npx hardhat ignition deploy ignition/modules/DeployStaking.ts --network bsc"
echo "npx hardhat ignition deploy ignition/modules/DeployStakingv3.ts --network bsc"
echo ""
echo "✅ Ensure you have:"
echo "   - BSC_PRIVATE_KEY in .env"
echo "   - BSCSCAN_API_KEY in .env"
echo "   - Sufficient BNB for gas fees"
