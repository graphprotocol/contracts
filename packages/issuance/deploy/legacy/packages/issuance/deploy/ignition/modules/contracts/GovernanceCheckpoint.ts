import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

/**
 * Governance Checkpoint Module
 *
 * Deploys a contract that can verify on-chain that governance actions have been completed.
 * Used by target modules to ensure prerequisites are met before proceeding.
 *
 * The checkpoint contract can verify:
 * - Proxy implementation upgrades have been completed
 * - Integration methods are available on contracts
 * - Minting authority has been granted
 * - Configuration parameters have been set
 */
const GovernanceCheckpointModule = buildModule('IssuanceStateVerifier', (m) => {
  const verifier = m.contract('IssuanceStateVerifier', [], {
    id: 'IssuanceStateVerifier',
  })

  return { verifier }
})

export default GovernanceCheckpointModule
