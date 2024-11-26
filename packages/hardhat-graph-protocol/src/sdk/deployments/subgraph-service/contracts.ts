import path from 'path'

import type {
  L2Curation,
  L2GNS,
  ServiceRegistry,
  SubgraphNFT,
} from '@graphprotocol/contracts'

import type {
  DisputeManager,
  SubgraphService,
} from '@graphprotocol/subgraph-service'
import type { ContractList } from '../../lib/contract'

export const SubgraphServiceContractNameList = [
  // @graphprotocol/contracts
  'L2Curation',
  'L2GNS',
  'SubgraphNFT',
  'ServiceRegistry',

  // @graphprotocol/subgraph-service
  'SubgraphService',
  'DisputeManager',
] as const

const root = path.resolve(__dirname, '../../../../..') // hardhat-graph-protocol root
export const CONTRACTS_ARTIFACTS_PATH = path.resolve(root, 'node_modules', '@graphprotocol/contracts/build/contracts')
export const SUBGRAPH_SERVICE_ARTIFACTS_PATH = path.resolve(root, 'node_modules', '@graphprotocol/subgraph-service/build/contracts')

export const SubgraphServiceArtifactsMap = {
  // @graphprotocol/contracts
  L2Curation: CONTRACTS_ARTIFACTS_PATH,
  L2GNS: CONTRACTS_ARTIFACTS_PATH,
  SubgraphNFT: CONTRACTS_ARTIFACTS_PATH,
  ServiceRegistry: CONTRACTS_ARTIFACTS_PATH,

  // @graphprotocol/subgraph-service
  SubgraphService: SUBGRAPH_SERVICE_ARTIFACTS_PATH,
  DisputeManager: SUBGRAPH_SERVICE_ARTIFACTS_PATH,
} as const

export interface SubgraphServiceContracts extends ContractList<SubgraphServiceContractName> {
  // @graphprotocol/contracts
  L2Curation: L2Curation
  L2GNS: L2GNS
  SubgraphNFT: SubgraphNFT
  ServiceRegistry: ServiceRegistry

  // @graphprotocol/subgraph-service
  SubgraphService: SubgraphService
  DisputeManager: DisputeManager

  // Aliases
  Curation: L2Curation
  GNS: L2GNS
}

export type SubgraphServiceContractName = (typeof SubgraphServiceContractNameList)[number]
