import type {
  HorizonStakingExtension,
  HorizonStaking as HorizonStakingMain,
  IEpochManagerToolshed,
  IGraphToken,
  IL2CurationToolshed,
  IRewardsManagerToolshed,
  IStaking,
} from '@graphprotocol/horizon'

// These are just type re-declarations to keep naming conventions consistent
export {
  IGraphToken as L2GraphToken,
  IEpochManagerToolshed as EpochManager,
  IRewardsManagerToolshed as RewardsManager,
  IL2CurationToolshed as L2Curation,
  IStaking as LegacyStaking,
}

export type HorizonStaking = HorizonStakingMain & HorizonStakingExtension
