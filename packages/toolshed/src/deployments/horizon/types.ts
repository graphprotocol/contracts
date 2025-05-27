import type {
  HorizonStakingExtension,
  HorizonStaking as HorizonStakingMain,
  IEpochManagerToolshed,
  IGNSToolshed,
  IGraphToken,
  IL2CurationToolshed,
  IRewardsManagerToolshed,
  IStaking,
  ISubgraphNFT,
} from '@graphprotocol/horizon'

// These are just type re-declarations to keep naming conventions consistent
export {
  IGraphToken as L2GraphToken,
  IEpochManagerToolshed as EpochManager,
  IRewardsManagerToolshed as RewardsManager,
  IL2CurationToolshed as L2Curation,
  IStaking as LegacyStaking,
  IGNSToolshed as L2GNS,
  ISubgraphNFT as SubgraphNFT,
}

export type HorizonStaking = HorizonStakingMain & HorizonStakingExtension
