import type {
  DisputeManager,
  L2Curation,
  L2GNS,
  LegacyDisputeManager,
  LegacyServiceRegistry,
  SubgraphNFT,
  SubgraphService,
} from '@graphprotocol/interfaces'

import type { ContractList } from '../contract'

export const SubgraphServiceContractNameList = [
  // @graphprotocol/contracts
  'L2Curation',
  'L2GNS',
  'SubgraphNFT',

  // @graphprotocol/subgraph-service
  'SubgraphService',
  'DisputeManager',

  // @graphprotocol/contracts - legacy
  'LegacyDisputeManager',
  'LegacyServiceRegistry',
] as const

export interface SubgraphServiceContracts extends ContractList<SubgraphServiceContractName> {
  // @graphprotocol/contracts
  L2Curation: L2Curation
  L2GNS: L2GNS
  SubgraphNFT: SubgraphNFT

  // @graphprotocol/subgraph-service
  SubgraphService: SubgraphService
  DisputeManager: DisputeManager

  // @graphprotocol/contracts - legacy
  LegacyDisputeManager: LegacyDisputeManager
  LegacyServiceRegistry: LegacyServiceRegistry

  // Aliases
  Curation: L2Curation
  GNS: L2GNS
}

export type SubgraphServiceContractName = (typeof SubgraphServiceContractNameList)[number]
