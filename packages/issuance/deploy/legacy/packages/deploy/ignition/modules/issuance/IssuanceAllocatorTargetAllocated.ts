import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import IssuanceAllocatorRef from './_refs/IssuanceAllocator'
import PilotAllocationRef from './_refs/PilotAllocation'

export default buildModule('IssuanceAllocatorTargetAllocated', (m) => {
  const { issuanceAllocator } = m.useModule(IssuanceAllocatorRef)
  const { pilotAllocation } = m.useModule(PilotAllocationRef)

  const verifier = m.contractAt('IssuanceStateVerifier', '0x0000000000000000000000000000000000000000')
  m.call(verifier, 'assertTargetAllocated', [issuanceAllocator, pilotAllocation], { id: 'AssertPilotAllocated' })

  return { issuanceAllocator, pilotAllocation }
})
