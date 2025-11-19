import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphTokenRef from '../horizon/GraphToken'
import IARef from './_refs/IssuanceAllocator'

/**
 * Checkpoint module: Asserts IssuanceAllocator has minter role on GraphToken
 *
 * This module uses IssuanceStateVerifier (stateless helper) to assert that governance
 * has granted minter role to IssuanceAllocator on GraphToken.
 *
 * IMPORTANT: This module will REVERT until governance executes addMinter().
 * It serves as a programmatic checkpoint/verification step.
 *
 * Usage:
 * 1. Deploy IA component (issuance/deploy package)
 * 2. Generate governance TX batch including addMinter (deploy/governance)
 * 3. Governance executes batch via Safe
 * 4. Run this module to verify (succeeds only after governance)
 */
export default buildModule('IssuanceAllocatorMinter', (m) => {
  const { graphToken } = m.useModule(GraphTokenRef)
  const { issuanceAllocator } = m.useModule(IARef)

  // IssuanceStateVerifier is stateless - we use it at a dummy address
  const verifier = m.contractAt('IssuanceStateVerifier', '0x0000000000000000000000000000000000000000')

  m.call(verifier, 'assertMinterRole', [graphToken, issuanceAllocator], {
    id: 'AssertIAMinterRole',
  })

  return { graphToken, issuanceAllocator }
})
