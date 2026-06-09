# Deployment Guide

This guide explains how to deploy the Staking and MultiDEXStaking contracts to Ethereum and BSC mainnets.

## Prerequisites

1. Create a `.env` file in the root directory with the following variables:
   ```
   BSC_PRIVATE_KEY=your_private_key_here
   ALCHEMY_API_KEY=your_alchemy_api_key_here
   ```

2. Optional: Add Position Manager addresses if different from defaults:
   ```
   ETH_PANCAKE_POSITION_MANAGER=0x...
   ETH_UNISWAP_POSITION_MANAGER=0x...
   BSC_PANCAKE_POSITION_MANAGER=0x...
   BSC_UNISWAP_POSITION_MANAGER=0x...
   ```

## Deployment Methods

### Method 1: Using Deployment Scripts (Recommended)

#### Deploy to Ethereum Mainnet
```bash
npm run deploy:ethereum
```

#### Deploy to BSC Mainnet
```bash
npm run deploy:bsc
```

### Method 2: Using Ignition CLI

#### Deploy Staking Contract to Ethereum
```bash
npx hardhat ignition deploy ignition/modules/DeployStaking.ts --network ethereum --parameters '{"DeployStakingModule":{"initialOwner":"YOUR_OWNER_ADDRESS"}}'
```

#### Deploy MultiDEXStaking Contract to Ethereum
```bash
npx hardhat ignition deploy ignition/modules/DeployStakingv3.ts --network ethereum --parameters '{"DeployStakingv3Module":{"pancakePositionManager":"0x...","uniswapPositionManager":"0xC36442b4a4522E871399CD717aBDD847Ab11FE88","initialOwner":"YOUR_OWNER_ADDRESS"}}'
```

#### Deploy Staking Contract to BSC
```bash
npx hardhat ignition deploy ignition/modules/DeployStaking.ts --network bsc --parameters '{"DeployStakingModule":{"initialOwner":"YOUR_OWNER_ADDRESS"}}'
```

#### Deploy MultiDEXStaking Contract to BSC
```bash
npx hardhat ignition deploy ignition/modules/DeployStakingv3.ts --network bsc --parameters '{"DeployStakingv3Module":{"pancakePositionManager":"0x46A15B0b27311cedF172AB29E4f4766fbE7F4364","uniswapPositionManager":"0x0000000000000000000000000000000000000000","initialOwner":"YOUR_OWNER_ADDRESS"}}'
```

### Method 3: Using Ignition Scripts

#### Deploy to Ethereum Mainnet (Ignition)
```bash
npm run deploy:ethereum:ignition
```

#### Deploy to BSC Mainnet (Ignition)
```bash
npm run deploy:bsc:ignition
```

## Default Position Manager Addresses

### Ethereum Mainnet
- **Uniswap V3 Position Manager**: `0xC36442b4a4522E871399CD717aBDD847Ab11FE88`
- **PancakeSwap Position Manager**: Set via environment variable or use zero address

### BSC Mainnet
- **PancakeSwap V3 Position Manager**: `0x46A15B0b27311cedF172AB29E4f4766fbE7F4364`
- **Uniswap Position Manager**: Not available on BSC (use zero address)

## Contract Addresses

After deployment, the scripts will output the deployed contract addresses. Save these for future reference.

## Verification

To verify contracts on block explorers, you can use:
```bash
npx hardhat verify --network ethereum <CONTRACT_ADDRESS> <CONSTRUCTOR_ARGS>
npx hardhat verify --network bsc <CONTRACT_ADDRESS> <CONSTRUCTOR_ARGS>
```

## Notes

- Make sure you have sufficient balance in your wallet for gas fees
- The deployment scripts will use the first account from your private key
- All contracts will be owned by the deployer address by default
- Position Manager addresses can be customized via environment variables
