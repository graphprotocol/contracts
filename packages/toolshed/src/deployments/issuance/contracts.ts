import type { DirectAllocation, IssuanceAllocator, RewardsEligibilityOracle } from '@graphprotocol/interfaces'

import type { ContractList } from '../contract'

export const GraphIssuanceContractNameList = [
  'IssuanceAllocator',
  'PilotAllocation',
  'RewardsEligibilityOracle',
] as const

export type GraphIssuanceContractName = (typeof GraphIssuanceContractNameList)[number]

export interface GraphIssuanceContracts extends ContractList<GraphIssuanceContractName> {
  IssuanceAllocator: IssuanceAllocator
  PilotAllocation: DirectAllocation
  RewardsEligibilityOracle: RewardsEligibilityOracle
}
