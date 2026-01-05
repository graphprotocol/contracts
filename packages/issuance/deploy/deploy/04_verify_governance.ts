import type { HardhatRuntimeEnvironment } from 'hardhat/types'
import type { DeployFunction } from 'hardhat-deploy/types'

/**
 * Verify governance and configuration for all issuance contracts
 *
 * This script verifies that issuance contracts are properly configured:
 * - Governor has GOVERNOR_ROLE on all contracts
 * - Pause guardian has PAUSE_ROLE on pausable contracts
 * - IssuanceAllocator configuration (rate, distribution state)
 * - Proxy admin ownership
 *
 * The issuance contracts use role-based access control (OpenZeppelin AccessControl)
 * rather than ownership patterns.
 *
 * This script is idempotent and runs as part of deployment to ensure proper
 * access control configuration.
 *
 * Governance pattern:
 * 1. Contracts deployed with initialize(governor) - grants GOVERNOR_ROLE
 * 2. Governor has full administrative access via role-based permissions
 * 3. Pause guardian has emergency pause capability
 * 4. No ownership transfer needed - roles are assigned atomically during initialization
 *
 * Usage:
 *   pnpm hardhat deploy --tags verify-governance --network <network>
 *
 * Or as part of full deployment:
 *   pnpm hardhat deploy --tags issuance --network <network>
 */
const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts, ethers } = hre
  const { log, read } = deployments
  const { governor } = await getNamedAccounts()

  const pauseGuardian = await getNamedAccounts().then((accounts) => accounts.pauseGuardian || governor)

  const contracts = ['IssuanceAllocator', 'PilotAllocation', 'RewardsEligibilityOracle']

  log('\n========== Governance and Configuration Verification ==========\n')

  // 1. Verify GOVERNOR_ROLE
  log('1. Verifying GOVERNOR_ROLE assignment...')
  for (const contractName of contracts) {
    const deployment = await deployments.getOrNull(contractName)
    if (!deployment) {
      log(`   Skipping ${contractName} - not deployed`)
      continue
    }

    try {
      const governorRole = (await read(contractName, 'GOVERNOR_ROLE')) as string
      const hasRole = (await read(contractName, 'hasRole', governorRole, governor)) as boolean

      if (hasRole) {
        log(`   ✓ ${contractName}: Governor has GOVERNOR_ROLE`)
      } else {
        log(`   ✗ ${contractName}: WARNING - Governor does NOT have GOVERNOR_ROLE`)
      }
    } catch (error) {
      log(`   ✗ ${contractName}: Error verifying governance: ${error}`)
    }
  }

  // 2. Verify PAUSE_ROLE
  log('\n2. Verifying PAUSE_ROLE assignment...')
  const pausableContracts = ['IssuanceAllocator', 'PilotAllocation', 'RewardsEligibilityOracle']
  for (const contractName of pausableContracts) {
    const deployment = await deployments.getOrNull(contractName)
    if (!deployment) continue

    try {
      const pauseRole = (await read(contractName, 'PAUSE_ROLE')) as string
      const hasPauseRole = (await read(contractName, 'hasRole', pauseRole, pauseGuardian)) as boolean

      if (hasPauseRole) {
        log(`   ✓ ${contractName}: Pause guardian has PAUSE_ROLE`)
      } else {
        log(`   ⚠ ${contractName}: Pause guardian does NOT have PAUSE_ROLE (will be granted in 05_configure)`)
      }
    } catch (error) {
      log(`   ⚠ ${contractName}: Cannot verify PAUSE_ROLE: ${error}`)
    }
  }

  // 3. Verify IssuanceAllocator configuration
  log('\n3. Verifying IssuanceAllocator configuration...')
  const iaDeployment = await deployments.getOrNull('IssuanceAllocator')
  if (iaDeployment) {
    try {
      const issuanceRate = (await read('IssuanceAllocator', 'getIssuancePerBlock')) as bigint
      const isPaused = (await read('IssuanceAllocator', 'paused')) as boolean
      const lastDistributionBlock = (await read('IssuanceAllocator', 'lastDistributionBlock')) as bigint
      const currentBlock = BigInt(await ethers.provider.getBlockNumber())

      log(`   Issuance rate: ${issuanceRate} tokens/block`)
      log(`   Paused: ${isPaused}`)
      log(`   Last distribution block: ${lastDistributionBlock}`)
      log(`   Current block: ${currentBlock}`)

      if (issuanceRate === 0n) {
        log(`   ⚠ Issuance rate is 0 (will be configured later)`)
      } else {
        log(`   ✓ Issuance rate configured`)
      }

      if (isPaused) {
        log(`   ✗ WARNING: Contract is PAUSED`)
      } else {
        log(`   ✓ Contract is not paused`)
      }

      if (lastDistributionBlock === 0n) {
        log(`   ⚠ Distribution not initialized (will be initialized in 05_configure)`)
      } else {
        log(`   ✓ Distribution initialized`)
      }
    } catch (error) {
      log(`   ✗ Error verifying IssuanceAllocator configuration: ${error}`)
    }
  }

  // 4. Verify proxy admin ownership
  log('\n4. Verifying GraphIssuanceProxyAdmin ownership...')
  const proxyAdminDeployment = await deployments.getOrNull('GraphIssuanceProxyAdmin')
  if (proxyAdminDeployment) {
    try {
      const owner = (await read('GraphIssuanceProxyAdmin', 'owner')) as string
      if (owner.toLowerCase() === governor.toLowerCase()) {
        log(`   ✓ ProxyAdmin owned by governor: ${owner}`)
      } else {
        log(`   ✗ WARNING: ProxyAdmin owned by ${owner}, expected ${governor}`)
      }
    } catch (error) {
      log(`   ✗ Error verifying ProxyAdmin ownership: ${error}`)
    }
  }

  log('\n========== Verification Complete ==========\n')
}

func.tags = ['verify-governance', 'issuance-governance', 'issuance']
func.dependencies = ['issuance-core'] // Requires all core contracts to be deployed
func.runAtTheEnd = true // Run after all other deployments
func.id = 'VerifyGovernance'

export default func
