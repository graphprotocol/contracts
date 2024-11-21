import type {
  Controller,
  EpochManager,
  GraphProxyAdmin,
  L2GraphToken,
  L2GraphTokenGateway,
  RewardsManager,
} from '@graphprotocol/contracts'
import type { Contract } from 'ethers'
import type { ContractList } from '../lib/contract'

export const GraphHorizonContractNameList = [
  'GraphProxyAdmin',
  'Controller',
  'EpochManager',
  'RewardsManager',
  'L2GraphToken',
  'L2GraphTokenGateway',
] as const

export type GraphHorizonContractName = (typeof GraphHorizonContractNameList)[number]

export interface GraphHorizonContracts extends ContractList<GraphHorizonContractName> {
  // Imports from @graphprotocol/contracts use ethers v5
  // We trick the type system by &ing the Contract type
  EpochManager: EpochManager & Contract
  RewardsManager: RewardsManager & Contract
  GraphProxyAdmin: GraphProxyAdmin & Contract
  Controller: Controller & Contract
  L2GraphToken: L2GraphToken & Contract
  L2GraphTokenGateway: L2GraphTokenGateway & Contract

  // Aliases
  GraphToken: L2GraphToken
  GraphTokenGateway: L2GraphTokenGateway

  // Iterator
  [Symbol.iterator]: () => Generator<Contract, void, void>
}
