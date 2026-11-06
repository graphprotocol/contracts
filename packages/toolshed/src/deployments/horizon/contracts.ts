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
  RecurringCollector,
  RewardsManager,
  SubgraphNFT,
} from '@graphprotocol/interfaces'

import type { ContractList } from '../contract'

export const GraphHorizonContractNameList = [
  // GraphProxyAdmin, Controller, EpochManager: @graphprotocol/graph-core; RewardsManager: @graphprotocol/issuance; L2GraphToken, L2GraphTokenGateway: @graphprotocol/graph-token
  'GraphProxyAdmin',
  'Controller',
  'EpochManager',
  'RewardsManager',
  'L2GraphToken',
  'L2GraphTokenGateway',

  // L2Curation, L2GNS: @graphprotocol/subgraph-service; SubgraphNFT: @graphprotocol/graph-token
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
  // GraphProxyAdmin, Controller, EpochManager: @graphprotocol/graph-core; RewardsManager: @graphprotocol/issuance; L2GraphToken, L2GraphTokenGateway: @graphprotocol/graph-token
  EpochManager: EpochManager
  RewardsManager: RewardsManager
  GraphProxyAdmin: GraphProxyAdmin
  Controller: Controller
  L2GraphToken: L2GraphToken

  // L2Curation, L2GNS: @graphprotocol/subgraph-service; SubgraphNFT: @graphprotocol/graph-token
  L2Curation: L2Curation
  L2GNS: L2GNS
  SubgraphNFT: SubgraphNFT

  // @graphprotocol/horizon
  HorizonStaking: HorizonStaking
  GraphPayments: GraphPayments
  PaymentsEscrow: PaymentsEscrow
  GraphTallyCollector: GraphTallyCollector
  RecurringCollector: RecurringCollector

  // Aliases
  GraphToken: L2GraphToken
  Curation: L2Curation
  GNS: L2GNS
  LegacyStaking: LegacyStaking
  LegacyRewardsManager: LegacyRewardsManager
}

export type GraphHorizonContractName = (typeof GraphHorizonContractNameList)[number]
