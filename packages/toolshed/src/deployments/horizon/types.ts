import type {
  HorizonStakingExtension,
  HorizonStaking as HorizonStakingMain,
  IEpochManager,
  IGraphToken,
  IL2CurationToolshed,
  IRewardsManagerToolshed,
  IStaking,
} from '@graphprotocol/horizon'

// These are just type re-declarations to keep naming conventions consistent
export {
  IGraphToken as L2GraphToken,
  IEpochManager as EpochManager,
  IRewardsManagerToolshed as RewardsManager,
  IL2CurationToolshed as L2Curation,
  IStaking as LegacyStaking,
}

export type HorizonStaking = HorizonStakingMain & HorizonStakingExtension

export enum PaymentTypes {
  QueryFee = 0,
  IndexingFee = 1,
  IndexingRewards = 2,
}

export enum ThawRequestType {
  Provision = 0,
  Delegation = 1,
}
