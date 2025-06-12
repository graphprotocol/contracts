import { resolvePackagePath } from '../../lib/path'
import type { ContractList } from '../contract'
import type {
  Controller,
  EpochManager,
  GraphPayments,
  GraphProxyAdmin,
  GraphTallyCollector,
  HorizonStaking,
  HorizonStakingExtension,
  L2Curation,
  L2GNS,
  L2GraphToken,
  LegacyStaking,
  PaymentsEscrow,
  RewardsManager,
  SubgraphNFT,
} from './types'

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
] as const

export const CONTRACTS_ARTIFACTS_PATH = resolvePackagePath('@graphprotocol/contracts', 'build/contracts')
export const HORIZON_ARTIFACTS_PATH = resolvePackagePath('@graphprotocol/horizon', 'build/contracts')

export const GraphHorizonArtifactsMap = {
  // @graphprotocol/contracts
  GraphProxyAdmin: CONTRACTS_ARTIFACTS_PATH,
  Controller: CONTRACTS_ARTIFACTS_PATH,
  EpochManager: CONTRACTS_ARTIFACTS_PATH,
  RewardsManager: CONTRACTS_ARTIFACTS_PATH,
  L2GraphToken: CONTRACTS_ARTIFACTS_PATH,
  L2GraphTokenGateway: CONTRACTS_ARTIFACTS_PATH,

  // @graphprotocol/contracts - subgraph-service compatibility
  L2Curation: CONTRACTS_ARTIFACTS_PATH,
  L2GNS: CONTRACTS_ARTIFACTS_PATH,
  SubgraphNFT: CONTRACTS_ARTIFACTS_PATH,

  // @graphprotocol/contracts - legacy
  LegacyStaking: CONTRACTS_ARTIFACTS_PATH,

  // @graphprotocol/horizon
  HorizonStaking: HORIZON_ARTIFACTS_PATH,
  GraphPayments: HORIZON_ARTIFACTS_PATH,
  PaymentsEscrow: HORIZON_ARTIFACTS_PATH,
  GraphTallyCollector: HORIZON_ARTIFACTS_PATH,
} as const

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
  HorizonStaking: HorizonStaking & HorizonStakingExtension
  GraphPayments: GraphPayments
  PaymentsEscrow: PaymentsEscrow
  GraphTallyCollector: GraphTallyCollector

  // Aliases
  GraphToken: L2GraphToken
  Curation: L2Curation
  GNS: L2GNS
  LegacyStaking: LegacyStaking
}

export type GraphHorizonContractName = (typeof GraphHorizonContractNameList)[number]
