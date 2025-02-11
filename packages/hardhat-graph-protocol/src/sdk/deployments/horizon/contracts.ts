import path from 'path'

import type {
  Controller,
  EpochManager,
  GraphProxyAdmin,
  L2GraphToken,
  L2GraphTokenGateway,
  RewardsManager,
} from '@graphprotocol/contracts'
import type {
  GraphPayments,
  GraphTallyCollector,
  HorizonStaking,
  PaymentsEscrow,
} from '@graphprotocol/horizon'
import type { ContractList } from '../../lib/contract'

export const GraphHorizonContractNameList = [
  // @graphprotocol/contracts
  'GraphProxyAdmin',
  'Controller',
  'EpochManager',
  'RewardsManager',
  'L2GraphToken',
  'L2GraphTokenGateway',

  // @graphprotocol/horizon
  'HorizonStaking',
  'GraphPayments',
  'PaymentsEscrow',
  'GraphTallyCollector',
] as const

const root = path.resolve(__dirname, '../../../../..') // hardhat-graph-protocol root
export const CONTRACTS_ARTIFACTS_PATH = path.resolve(root, 'node_modules', '@graphprotocol/contracts/build/contracts')
export const HORIZON_ARTIFACTS_PATH = path.resolve(root, 'node_modules', '@graphprotocol/horizon/build/contracts')

export const GraphHorizonArtifactsMap = {
  // @graphprotocol/contracts
  GraphProxyAdmin: CONTRACTS_ARTIFACTS_PATH,
  Controller: CONTRACTS_ARTIFACTS_PATH,
  EpochManager: CONTRACTS_ARTIFACTS_PATH,
  RewardsManager: CONTRACTS_ARTIFACTS_PATH,
  L2GraphToken: CONTRACTS_ARTIFACTS_PATH,
  L2GraphTokenGateway: CONTRACTS_ARTIFACTS_PATH,

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
  L2GraphTokenGateway: L2GraphTokenGateway

  // @graphprotocol/horizon
  HorizonStaking: HorizonStaking
  GraphPayments: GraphPayments
  PaymentsEscrow: PaymentsEscrow
  GraphTallyCollector: GraphTallyCollector

  // Aliases
  GraphToken: L2GraphToken
  GraphTokenGateway: L2GraphTokenGateway
}

export type GraphHorizonContractName = (typeof GraphHorizonContractNameList)[number]
