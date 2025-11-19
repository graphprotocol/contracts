import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import RewardsManagerRef from '../horizon/RewardsManager'
import IARef from './_refs/IssuanceAllocator'

/**
 * Checkpoint module: Asserts IssuanceAllocator is integrated with RewardsManager
 *
 * This module uses IssuanceStateVerifier (stateless helper) to assert that governance
 * has executed the setIssuanceAllocator() call on RewardsManager.
 *
 * IMPORTANT: This module will REVERT until governance executes the integration.
 * It serves as a programmatic checkpoint/verification step.
 *
 * Usage:
 * 1. Deploy IA component (issuance/deploy package)
 * 2. Generate governance TX batch (deploy/governance)
 * 3. Governance executes batch via Safe
 * 4. Run this module to verify (succeeds only after governance)
 */
export default buildModule('IssuanceAllocatorActive', (m) => {
  const { rewardsManager } = m.useModule(RewardsManagerRef)
  const { issuanceAllocator } = m.useModule(IARef)

  // IssuanceStateVerifier is stateless - we use it at a dummy address
  const verifier = m.contractAt('IssuanceStateVerifier', '0x0000000000000000000000000000000000000000')

  m.call(verifier, 'assertIssuanceAllocatorSet', [rewardsManager, issuanceAllocator], {
    id: 'AssertIAIntegration',
  })

  return { rewardsManager, issuanceAllocator }
})
