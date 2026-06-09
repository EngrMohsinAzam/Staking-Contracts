# Deploy to Ethereum Mainnet using Ignition

## Using Ignition CLI

### Deploy Staking Contract
```bash
npx hardhat ignition deploy ignition/modules/DeployStaking.ts --network ethereum --parameters '{"DeployStakingModule":{"initialOwner":"YOUR_OWNER_ADDRESS"}}'
```

### Deploy MultiDEXStaking Contract
```bash
npx hardhat ignition deploy ignition/modules/DeployStakingv3.ts --network ethereum --parameters '{"DeployStakingv3Module":{"pancakePositionManager":"0x...","uniswapPositionManager":"0xC36442b4a4522E871399CD717aBDD847Ab11FE88","initialOwner":"YOUR_OWNER_ADDRESS"}}'
```

## Using Deployment Scripts

Alternatively, use the deployment script:
```bash
npm run deploy:ethereum
```

Make sure your `.env` file has:
- `BSC_PRIVATE_KEY` - Your private key (used for both networks)
- `ALCHEMY_API_KEY` - Your Alchemy API key for Ethereum
- `ETH_PANCAKE_POSITION_MANAGER` - Optional, PancakeSwap Position Manager on Ethereum
- `ETH_UNISWAP_POSITION_MANAGER` - Optional, defaults to Uniswap V3 Position Manager
