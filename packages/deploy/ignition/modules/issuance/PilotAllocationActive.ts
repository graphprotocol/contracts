import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import IARef from './_refs/IssuanceAllocator'
import PARef from './_refs/PilotAllocation'

/**
 * Checkpoint module: Asserts PilotAllocation is configured in IssuanceAllocator
 *
 * This module uses IssuanceStateVerifier (stateless helper) to assert that governance
 * has configured PilotAllocation as an allocation target in IssuanceAllocator.
 *
 * IMPORTANT: This module will REVERT until governance executes the allocation configuration.
 * It serves as a programmatic checkpoint/verification step.
 *
 * Usage:
 * 1. Deploy PilotAllocation component (issuance/deploy package)
 * 2. Generate governance TX batch for allocation configuration
 * 3. Governance executes batch via Safe (setTargetAllocation)
 * 4. Run this module to verify (succeeds only after governance)
 */
export default buildModule('PilotAllocationActive', (m) => {
  const { issuanceAllocator } = m.useModule(IARef)
  const { pilotAllocation } = m.useModule(PARef)

  // IssuanceStateVerifier is stateless - we use it at a dummy address
  const verifier = m.contractAt('IssuanceStateVerifier', '0x0000000000000000000000000000000000000000')

  m.call(verifier, 'assertTargetAllocated', [issuanceAllocator, pilotAllocation], {
    id: 'AssertPAAllocation',
  })

  return { issuanceAllocator, pilotAllocation }
})
