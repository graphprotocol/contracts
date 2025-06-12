
import { resolvePackagePath } from '../../lib/path'
import type { ContractList } from '../contract'
import type { DisputeManager, L2Curation, L2GNS, LegacyDisputeManager, LegacyServiceRegistry, SubgraphNFT, SubgraphService } from './types'

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

export const CONTRACTS_ARTIFACTS_PATH = resolvePackagePath('@graphprotocol/contracts', 'build/contracts')
export const SUBGRAPH_SERVICE_ARTIFACTS_PATH = resolvePackagePath('@graphprotocol/subgraph-service', 'build/contracts')

export const SubgraphServiceArtifactsMap = {
  // @graphprotocol/contracts
  L2Curation: CONTRACTS_ARTIFACTS_PATH,
  L2GNS: CONTRACTS_ARTIFACTS_PATH,
  SubgraphNFT: CONTRACTS_ARTIFACTS_PATH,

  // @graphprotocol/subgraph-service
  SubgraphService: SUBGRAPH_SERVICE_ARTIFACTS_PATH,
  DisputeManager: SUBGRAPH_SERVICE_ARTIFACTS_PATH,

  // @graphprotocol/contracts - legacy
  LegacyDisputeManager: CONTRACTS_ARTIFACTS_PATH,
  LegacyServiceRegistry: CONTRACTS_ARTIFACTS_PATH,
} as const

export interface SubgraphServiceContracts extends ContractList<SubgraphServiceContractName> {
  // @graphprotocol/contracts
  L2Curation: L2Curation
  L2GNS: L2GNS
  SubgraphNFT: SubgraphNFT

  // @graphprotocol/subgraph-service
  SubgraphService: SubgraphService
  DisputeManager: DisputeManager

  // Aliases
  Curation: L2Curation
  GNS: L2GNS

  // @graphprotocol/contracts - legacy
  LegacyDisputeManager: LegacyDisputeManager
  LegacyServiceRegistry: LegacyServiceRegistry
}

export type SubgraphServiceContractName = (typeof SubgraphServiceContractNameList)[number]
