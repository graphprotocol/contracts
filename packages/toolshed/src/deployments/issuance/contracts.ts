import type { DirectAllocation, IssuanceAllocator, RewardsEligibilityOracle } from '@graphprotocol/issuance/types'
import type { Contract } from 'ethers'

import type { ContractList } from '../contract'

export const GraphIssuanceContractNameList = [
  'DirectAllocation_Implementation',
  'IssuanceAllocator',
  'NetworkOperator',
  'PilotAllocation',
  'ReclaimedRewardsForCloseAllocation',
  'ReclaimedRewardsForIndexerIneligible',
  'ReclaimedRewardsForStalePoi',
  'ReclaimedRewardsForSubgraphDenied',
  'ReclaimedRewardsForZeroPoi',
  'RewardsEligibilityOracle',
] as const

export type GraphIssuanceContractName = (typeof GraphIssuanceContractNameList)[number]

export interface GraphIssuanceContracts extends ContractList<GraphIssuanceContractName> {
  DirectAllocation_Implementation: Contract
  IssuanceAllocator: IssuanceAllocator
  NetworkOperator: Contract // Address holder for network operator (not an actual contract)
  PilotAllocation: DirectAllocation
  ReclaimedRewardsForCloseAllocation: DirectAllocation
  ReclaimedRewardsForIndexerIneligible: DirectAllocation
  ReclaimedRewardsForStalePoi: DirectAllocation
  ReclaimedRewardsForSubgraphDenied: DirectAllocation
  ReclaimedRewardsForZeroPoi: DirectAllocation
  RewardsEligibilityOracle: RewardsEligibilityOracle
}
