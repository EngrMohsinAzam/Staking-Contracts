# Deploy to BSC Mainnet using Ignition

## Using Ignition CLI

### Deploy Staking Contract
```bash
npx hardhat ignition deploy ignition/modules/DeployStaking.ts --network bsc --parameters '{"DeployStakingModule":{"initialOwner":"YOUR_OWNER_ADDRESS"}}'
```

### Deploy MultiDEXStaking Contract
```bash
npx hardhat ignition deploy ignition/modules/DeployStakingv3.ts --network bsc --parameters '{"DeployStakingv3Module":{"pancakePositionManager":"0x46A15B0b27311cedF172AB29E4f4766fbE7F4364","uniswapPositionManager":"0x0000000000000000000000000000000000000000","initialOwner":"YOUR_OWNER_ADDRESS"}}'
```

## Using Deployment Scripts

Alternatively, use the deployment script:
```bash
npm run deploy:bsc
```

Make sure your `.env` file has:
- `BSC_PRIVATE_KEY` - Your private key
- `BSC_PANCAKE_POSITION_MANAGER` - Optional, defaults to PancakeSwap V3 Position Manager on BSC
- `BSC_UNISWAP_POSITION_MANAGER` - Optional, Uniswap is not on BSC
