import type {
  DirectAllocation,
  GraphProxyAdmin,
  IssuanceAllocator,
  RewardsEligibilityOracle,
} from '@graphprotocol/interfaces'

import type { ContractList } from '../contract'

export const GraphIssuanceContractNameList = [
  'GraphProxyAdmin2',
  'IssuanceAllocator',
  'PilotAllocation',
  'RewardsEligibilityOracle',
] as const

export type GraphIssuanceContractName = (typeof GraphIssuanceContractNameList)[number]

export interface GraphIssuanceContracts extends ContractList<GraphIssuanceContractName> {
  GraphProxyAdmin2: GraphProxyAdmin
  IssuanceAllocator: IssuanceAllocator
  PilotAllocation: DirectAllocation
  RewardsEligibilityOracle: RewardsEligibilityOracle
}
