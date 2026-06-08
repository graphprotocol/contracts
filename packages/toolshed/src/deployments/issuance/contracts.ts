import type {
  DirectAllocation,
  IssuanceAllocator,
  RecurringAgreementManager,
  RewardsEligibilityOracle,
} from '@graphprotocol/issuance/types'
import type { Contract } from 'ethers'

import type { ContractList } from '../contract'

export const GraphIssuanceContractNameList = [
  'DefaultAllocation',
  'DirectAllocation_Implementation',
  'IssuanceAllocator',
  'NetworkOperator',
  'ReclaimedRewards',
  'RecurringAgreementManager',
  'RewardsEligibilityOracleA',
  'RewardsEligibilityOracleB',
  'RewardsEligibilityOracleMock',
] as const

export type GraphIssuanceContractName = (typeof GraphIssuanceContractNameList)[number]

export interface GraphIssuanceContracts extends ContractList<GraphIssuanceContractName> {
  DefaultAllocation: DirectAllocation
  DirectAllocation_Implementation: Contract
  IssuanceAllocator: IssuanceAllocator
  NetworkOperator: Contract // Address holder for network operator (not an actual contract)
  ReclaimedRewards: DirectAllocation
  RecurringAgreementManager: RecurringAgreementManager
  RewardsEligibilityOracleA: RewardsEligibilityOracle
  RewardsEligibilityOracleB: RewardsEligibilityOracle
  RewardsEligibilityOracleMock: Contract
}
