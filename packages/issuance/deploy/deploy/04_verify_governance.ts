import type { HardhatRuntimeEnvironment } from 'hardhat/types'
import type { DeployFunction } from 'hardhat-deploy/types'

/**
 * Verify governor role assignment for all issuance contracts
 *
 * This script verifies that the governor has the GOVERNOR_ROLE on all issuance
 * contracts after deployment. The issuance contracts use role-based access control
 * (OpenZeppelin AccessControl) rather than ownership patterns.
 *
 * This script is idempotent and runs as part of deployment to ensure proper
 * access control configuration.
 *
 * Governance pattern:
 * 1. Contracts deployed with initialize(governor) - grants GOVERNOR_ROLE
 * 2. Governor has full administrative access via role-based permissions
 * 3. No ownership transfer needed - roles are assigned atomically during initialization
 *
 * Usage:
 *   pnpm hardhat deploy --tags verify-governance --network <network>
 *
 * Or as part of full deployment:
 *   pnpm hardhat deploy --tags issuance --network <network>
 */
const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts } = hre
  const { log, read } = deployments
  const { governor } = await getNamedAccounts()

  const contracts = ['IssuanceAllocator', 'PilotAllocation', 'RewardsEligibilityOracle']

  log('Verifying governor role assignment for issuance contracts...')

  for (const contractName of contracts) {
    const deployment = await deployments.getOrNull(contractName)
    if (!deployment) {
      log(`Skipping ${contractName} - not deployed`)
      continue
    }

    try {
      // Get the GOVERNOR_ROLE identifier
      const governorRole = (await read(contractName, 'GOVERNOR_ROLE')) as string

      // Check if governor has the GOVERNOR_ROLE
      const hasRole = (await read(contractName, 'hasRole', governorRole, governor)) as boolean

      if (hasRole) {
        log(`✓ ${contractName}: Governor has GOVERNOR_ROLE`)
      } else {
        log(`✗ ${contractName}: WARNING - Governor does NOT have GOVERNOR_ROLE`)
      }
    } catch (error) {
      log(`${contractName}: Error verifying governance: ${error}`)
    }
  }

  log('Governor role verification complete')
}

func.tags = ['verify-governance', 'issuance-governance', 'issuance']
func.dependencies = ['issuance-core'] // Requires all core contracts to be deployed
func.runAtTheEnd = true // Run after all other deployments
func.id = 'VerifyGovernance'

export default func
