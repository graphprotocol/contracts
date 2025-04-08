import { resolveNodeModulesPath } from '../../lib/path'

import type {
  Controller,
  GraphPayments,
  GraphProxyAdmin,
  GraphTallyCollector,
  HorizonStaking,
  HorizonStakingExtension,
  PaymentsEscrow,
} from '@graphprotocol/horizon'
import type {
  EpochManager,
  L2Curation,
  L2GraphToken,
  RewardsManager,
} from './types'
import type { ContractList } from '../contract'

export const GraphHorizonContractNameList = [
  // @graphprotocol/contracts
  'GraphProxyAdmin',
  'Controller',
  'EpochManager',
  'RewardsManager',
  'L2GraphToken',
  'L2GraphTokenGateway',
  'L2Curation',

  // @graphprotocol/horizon
  'HorizonStaking',
  'GraphPayments',
  'PaymentsEscrow',
  'GraphTallyCollector',
] as const

export const CONTRACTS_ARTIFACTS_PATH = resolveNodeModulesPath('@graphprotocol/contracts/build/contracts')
export const HORIZON_ARTIFACTS_PATH = resolveNodeModulesPath('@graphprotocol/horizon/build/contracts')

export const GraphHorizonArtifactsMap = {
  // @graphprotocol/contracts
  GraphProxyAdmin: CONTRACTS_ARTIFACTS_PATH,
  Controller: CONTRACTS_ARTIFACTS_PATH,
  EpochManager: CONTRACTS_ARTIFACTS_PATH,
  RewardsManager: CONTRACTS_ARTIFACTS_PATH,
  L2GraphToken: CONTRACTS_ARTIFACTS_PATH,
  L2GraphTokenGateway: CONTRACTS_ARTIFACTS_PATH,
  L2Curation: CONTRACTS_ARTIFACTS_PATH,

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
  // L2GraphTokenGateway: L2GraphTokenGateway
  L2Curation: L2Curation // Actually a subgraph service contract

  // @graphprotocol/horizon
  HorizonStaking: HorizonStaking & HorizonStakingExtension
  GraphPayments: GraphPayments
  PaymentsEscrow: PaymentsEscrow
  GraphTallyCollector: GraphTallyCollector

  // Aliases
  GraphToken: L2GraphToken
  // GraphTokenGateway: L2GraphTokenGateway
  Curation: L2Curation
}

export type GraphHorizonContractName = (typeof GraphHorizonContractNameList)[number]
