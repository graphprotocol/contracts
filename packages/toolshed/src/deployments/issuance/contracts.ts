import type { DirectAllocation, IssuanceAllocator, RewardsEligibilityOracle } from '@graphprotocol/interfaces'
import type { ProxyAdmin } from '@openzeppelin/contracts'

import type { ContractList } from '../contract'

export const GraphIssuanceContractNameList = [
  'GraphIssuanceProxyAdmin',
  'IssuanceAllocator',
  'PilotAllocation',
  'RewardsEligibilityOracle',
] as const

export type GraphIssuanceContractName = (typeof GraphIssuanceContractNameList)[number]

export interface GraphIssuanceContracts extends ContractList<GraphIssuanceContractName> {
  GraphIssuanceProxyAdmin: ProxyAdmin
  IssuanceAllocator: IssuanceAllocator
  PilotAllocation: DirectAllocation
  RewardsEligibilityOracle: RewardsEligibilityOracle
}
