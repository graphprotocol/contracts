import type {
  Controller,
  EpochManager,
  GraphPayments,
  GraphProxyAdmin,
  GraphTallyCollector,
  HorizonStaking,
  L2Curation,
  L2GNS,
  L2GraphToken,
  LegacyRewardsManager,
  LegacyStaking,
  PaymentsEscrow,
  RewardsManager,
  SubgraphNFT,
} from '@graphprotocol/interfaces'

import type { ContractList } from '../contract'

export const GraphHorizonContractNameList = [
  // @graphprotocol/contracts
  'GraphProxyAdmin',
  'Controller',
  'EpochManager',
  'RewardsManager',
  'L2GraphToken',
  'L2GraphTokenGateway',

  // @graphprotocol/contracts - subgraph-service compatibility
  'L2Curation',
  'L2GNS',
  'SubgraphNFT',

  // @graphprotocol/horizon
  'HorizonStaking',
  'GraphPayments',
  'PaymentsEscrow',
  'GraphTallyCollector',
  'RecurringCollector',
] as const

export interface GraphHorizonContracts extends ContractList<GraphHorizonContractName> {
  // @graphprotocol/contracts
  EpochManager: EpochManager
  RewardsManager: RewardsManager
  GraphProxyAdmin: GraphProxyAdmin
  Controller: Controller
  L2GraphToken: L2GraphToken

  // @graphprotocol/contracts - subgraph-service compatibility
  L2Curation: L2Curation
  L2GNS: L2GNS
  SubgraphNFT: SubgraphNFT

  // @graphprotocol/horizon
  HorizonStaking: HorizonStaking
  GraphPayments: GraphPayments
  PaymentsEscrow: PaymentsEscrow
  GraphTallyCollector: GraphTallyCollector

  // Aliases
  GraphToken: L2GraphToken
  Curation: L2Curation
  GNS: L2GNS
  LegacyStaking: LegacyStaking
  LegacyRewardsManager: LegacyRewardsManager
}

export type GraphHorizonContractName = (typeof GraphHorizonContractNameList)[number]
