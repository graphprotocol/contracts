import type {
  HorizonStaking as HorizonStakingMain,
  HorizonStakingExtension,
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
  IEpochManagerToolshed as EpochManager,
  IL2CurationToolshed as L2Curation,
  IGNSToolshed as L2GNS,
  IGraphToken as L2GraphToken,
  IStaking as LegacyStaking,
  IRewardsManagerToolshed as RewardsManager,
  ISubgraphNFT as SubgraphNFT,
}

export type HorizonStaking = HorizonStakingMain & HorizonStakingExtension
