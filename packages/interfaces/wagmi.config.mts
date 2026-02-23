import { defineConfig, type Config } from '@wagmi/cli'
import { Abi } from 'viem'

import GraphToken from './artifacts/contracts/contracts/token/IGraphToken.sol/IGraphToken.json'
import L2GNS from './artifacts/contracts/toolshed/IL2GNSToolshed.sol/IL2GNSToolshed.json'
import L2Curation from './artifacts/contracts/toolshed/IL2CurationToolshed.sol/IL2CurationToolshed.json'
import HorizonStaking from './artifacts/contracts/toolshed/IHorizonStakingToolshed.sol/IHorizonStakingToolshed.json'
import EpochManager from './artifacts/contracts/toolshed/IEpochManagerToolshed.sol/IEpochManagerToolshed.json'
import RewardsManager from './artifacts/contracts/toolshed/IRewardsManagerToolshed.sol/IRewardsManagerToolshed.json'
import L2GraphTokenGateway from './artifacts/contracts/contracts/l2/gateway/IL2GraphTokenGateway.sol/IL2GraphTokenGateway.json'
import GraphTokenLockWallet from './artifacts/contracts/toolshed/IGraphTokenLockWalletToolshed.sol/IGraphTokenLockWalletToolshed.json'

// Only generate wagmi types for contracts that are used by the Explorer
export default defineConfig({
  out: 'wagmi/generated.ts',
  contracts: [
    {
      name: 'L2GNS',
      abi: L2GNS.abi as Abi,
    },
    {
      name: 'L2Curation',
      abi: L2Curation.abi as Abi,
    },
    {
      name: 'L2GraphToken',
      abi: GraphToken.abi as Abi,
    },
    {
      name: 'HorizonStaking',
      abi: HorizonStaking.abi as Abi,
    },
    {
      name: 'EpochManager',
      abi: EpochManager.abi as Abi,
    },
    {
      name: 'RewardsManager',
      abi: RewardsManager.abi as Abi,
    },
    {
      name: 'L2GraphTokenGateway',
      abi: L2GraphTokenGateway.abi as Abi,
    },
    {
      name: 'GraphTokenLockWallet',
      abi: GraphTokenLockWallet.abi as Abi,
    },
  ],
  plugins: []
}) as Config
