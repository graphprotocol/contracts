import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import IssuanceAllocatorActive from './IssuanceAllocatorActive'
import IssuanceAllocatorMinter from './IssuanceAllocatorMinter'
import IssuanceAllocatorTargetAllocated from './IssuanceAllocatorTargetAllocated'

// PilotAllocationActive is a composition-only target. It verifies that:
// - IssuanceAllocator is set on RewardsManager (IssuanceAllocatorActive)
// - IssuanceAllocator has minter role on GraphToken (IssuanceAllocatorMinter)
// - PilotAllocation has a non-zero allocation in IssuanceAllocator (IssuanceAllocatorTargetAllocated)
// It does not itself perform governance calls; those are executed externally.
export default buildModule('PilotAllocationActive', (m) => {
  const iaActive = m.useModule(IssuanceAllocatorActive)
  const iaMinter = m.useModule(IssuanceAllocatorMinter)
  const targetAllocated = m.useModule(IssuanceAllocatorTargetAllocated)

  return { iaActive, iaMinter, targetAllocated }
})
