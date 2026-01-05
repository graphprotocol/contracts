import type { DirectAllocation, IssuanceAllocator, RewardsEligibilityOracle } from '@graphprotocol/interfaces'
import type { Contract } from 'ethers'

import type { ContractList } from '../contract'

export const GraphIssuanceContractNameList = [
  'GraphIssuanceProxyAdmin',
  'IssuanceAllocator',
  'PilotAllocation',
  'RewardsEligibilityOracle',
] as const

export type GraphIssuanceContractName = (typeof GraphIssuanceContractNameList)[number]

export interface GraphIssuanceContracts extends ContractList<GraphIssuanceContractName> {
  GraphIssuanceProxyAdmin: Contract
  IssuanceAllocator: IssuanceAllocator
  PilotAllocation: DirectAllocation
  RewardsEligibilityOracle: RewardsEligibilityOracle
}
