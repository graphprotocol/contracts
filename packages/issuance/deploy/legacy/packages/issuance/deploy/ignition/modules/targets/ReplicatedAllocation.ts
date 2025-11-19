import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import IssuanceAllocatorModule from '../contracts/IssuanceAllocator'

/**
 * Replicated Allocation Target
 *
 * Deploys IssuanceAllocator ready to replicate current issuance behavior.
 * Base state - deployed and ready, replicates current issuance per block with 100% allocated to RewardsManager.
 */
const ReplicatedAllocationTarget = buildModule('ReplicatedAllocation', (m) => {
  // Deploy IssuanceAllocator (diagram: ReplicatedAllocation --> IssuanceAllocator)
  const { issuanceAllocator, implementation } = m.useModule(IssuanceAllocatorModule)

  return {
    issuanceAllocator,
    implementation,
  }
})

export default ReplicatedAllocationTarget
