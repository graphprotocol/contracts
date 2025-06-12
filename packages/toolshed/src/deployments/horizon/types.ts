import type {
  IController,
  IEpochManagerToolshed,
  IGNSToolshed,
  IGraphPayments,
  IGraphProxyAdmin,
  IGraphTallyCollector,
  IGraphToken,
  IHorizonStaking,
  IHorizonStakingExtension,
  IL2CurationToolshed,
  IPaymentsEscrow,
  IRewardsManagerToolshed,
  IStaking,
  ISubgraphNFT,
} from '@graphprotocol/interfaces'

// These are just type re-declarations to keep naming conventions consistent
type HorizonStaking = IHorizonStaking & IHorizonStakingExtension

export {
  IController as Controller,
  IEpochManagerToolshed as EpochManager,
  IGraphPayments as GraphPayments,
  IGraphProxyAdmin as GraphProxyAdmin,
  IGraphTallyCollector as GraphTallyCollector,
  HorizonStaking,
  IHorizonStakingExtension as HorizonStakingExtension,
  IL2CurationToolshed as L2Curation,
  IGNSToolshed as L2GNS,
  IGraphToken as L2GraphToken,
  IStaking as LegacyStaking,
  IPaymentsEscrow as PaymentsEscrow,
  IRewardsManagerToolshed as RewardsManager,
  ISubgraphNFT as SubgraphNFT,
}
