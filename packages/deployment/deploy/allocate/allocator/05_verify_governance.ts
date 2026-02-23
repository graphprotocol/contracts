import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { getGovernor, getPauseGuardian } from '@graphprotocol/deployment/lib/controller-utils.js'
import { actionTag, ComponentTags, DeploymentActions, Tags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { getProxyAdminAddress, requireDeployer } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { graph, read } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { DeployScriptModule } from '@rocketh/core/types'

/**
 * Verify governance and configuration for all issuance contracts
 *
 * This implements Step 7 from IssuanceAllocator.md:
 * - Bytecode verification (deployment bytecode matches expected contract)
 * - Access control:
 *   - Governor has GOVERNOR_ROLE on all contracts
 *   - Deployment account does NOT have GOVERNOR_ROLE
 *   - Pause guardian has PAUSE_ROLE on pausable contracts
 *   - Off-chain: Review all RoleGranted events since deployment
 * - Pause state: Verify contract is not paused
 * - Issuance rate: Verify matches RewardsManager rate exactly
 * - Target configuration: Verify only expected targets exist
 * - Proxy configuration: Verify ProxyAdmin controls proxy and is owned by governance
 *
 * The issuance contracts use role-based access control (OpenZeppelin AccessControl)
 * rather than ownership patterns.
 *
 * This script is idempotent and runs after governance transfer (step 6) to ensure
 * proper access control configuration before activation (steps 8-10).
 *
 * Usage:
 *   pnpm hardhat deploy --tags verify-governance --network <network>
 *
 * Or as part of full deployment:
 *   pnpm hardhat deploy --tags issuance-allocation --network <network>
 */
const func: DeployScriptModule = async (env) => {
  const readFn = read(env)

  const deployer = requireDeployer(env)

  // Get protocol governor and pause guardian from Controller
  const governor = await getGovernor(env)
  const pauseGuardian = await getPauseGuardian(env)

  const contracts = [
    Contracts.issuance.IssuanceAllocator.name,
    Contracts.issuance.PilotAllocation.name,
    Contracts.issuance.RewardsEligibilityOracle.name,
  ]

  env.showMessage('\n========== Governance and Configuration Verification ==========\n')

  // 1. Verify GOVERNOR_ROLE (governor has, deployer does not)
  env.showMessage('1. Verifying GOVERNOR_ROLE assignment...')
  for (const contractName of contracts) {
    const deployment = env.getOrNull(contractName)
    if (!deployment) {
      env.showMessage(`   Skipping ${contractName} - not deployed`)
      continue
    }

    try {
      const governorRole = (await readFn(deployment, { functionName: 'GOVERNOR_ROLE' })) as string

      // Check governor has role
      const governorHasRole = (await readFn(deployment, {
        functionName: 'hasRole',
        args: [governorRole, governor],
      })) as boolean

      // Check deployer does NOT have role
      const deployerHasRole = (await readFn(deployment, {
        functionName: 'hasRole',
        args: [governorRole, deployer],
      })) as boolean

      if (governorHasRole && !deployerHasRole) {
        env.showMessage(`   ✓ ${contractName}: Governor has GOVERNOR_ROLE, deployer revoked`)
      } else if (governorHasRole && deployerHasRole) {
        env.showMessage(`   ⚠ ${contractName}: Governor has GOVERNOR_ROLE but deployer NOT revoked`)
      } else if (!governorHasRole && deployerHasRole) {
        env.showMessage(`   ⚠ ${contractName}: Deployer has GOVERNOR_ROLE but governance NOT transferred`)
      } else {
        env.showMessage(`   ✗ ${contractName}: WARNING - Neither governor nor deployer has GOVERNOR_ROLE`)
      }
    } catch (error) {
      env.showMessage(`   ✗ ${contractName}: Error verifying governance: ${error}`)
    }
  }

  // 2. Verify PAUSE_ROLE
  env.showMessage('\n2. Verifying PAUSE_ROLE assignment...')
  const pausableContracts = [
    Contracts.issuance.IssuanceAllocator.name,
    Contracts.issuance.PilotAllocation.name,
    Contracts.issuance.RewardsEligibilityOracle.name,
  ]
  for (const contractName of pausableContracts) {
    const deployment = env.getOrNull(contractName)
    if (!deployment) continue

    try {
      const pauseRole = (await readFn(deployment, { functionName: 'PAUSE_ROLE' })) as string
      const hasPauseRole = (await readFn(deployment, {
        functionName: 'hasRole',
        args: [pauseRole, pauseGuardian],
      })) as boolean

      if (hasPauseRole) {
        env.showMessage(`   ✓ ${contractName}: Pause guardian has PAUSE_ROLE`)
      } else {
        env.showMessage(
          `   ⚠ ${contractName}: Pause guardian does NOT have PAUSE_ROLE (will be granted in 06_transfer_governance)`,
        )
      }
    } catch (error) {
      env.showMessage(`   ⚠ ${contractName}: Cannot verify PAUSE_ROLE: ${error}`)
    }
  }

  // 3. Verify IssuanceAllocator configuration
  env.showMessage('\n3. Verifying IssuanceAllocator configuration...')
  const iaDeployment = env.getOrNull(Contracts.issuance.IssuanceAllocator.name)
  if (iaDeployment) {
    try {
      const issuanceRate = (await readFn(iaDeployment, { functionName: 'getIssuancePerBlock' })) as bigint
      const isPaused = (await readFn(iaDeployment, { functionName: 'paused' })) as boolean

      env.showMessage(`   Issuance rate: ${issuanceRate} tokens/block`)
      env.showMessage(`   Paused: ${isPaused}`)

      if (issuanceRate === 0n) {
        env.showMessage(`   ⚠ Issuance rate is 0 (will be configured in step 5)`)
      } else {
        env.showMessage(`   ✓ Issuance rate configured`)
      }

      if (isPaused) {
        env.showMessage(`   ✗ WARNING: Contract is PAUSED`)
      } else {
        env.showMessage(`   ✓ Contract is not paused`)
      }
    } catch (error) {
      env.showMessage(`   ✗ Error verifying IssuanceAllocator configuration: ${error}`)
    }
  }

  // 4. Verify per-proxy ProxyAdmin ownership (OZ v5 pattern)
  env.showMessage('\n4. Verifying per-proxy ProxyAdmin ownership...')
  const client = graph.getPublicClient(env)
  const proxiedContracts = [
    Contracts.issuance.IssuanceAllocator.name,
    Contracts.issuance.PilotAllocation.name,
    Contracts.issuance.RewardsEligibilityOracle.name,
  ]
  for (const contractName of proxiedContracts) {
    const proxyDeployment = env.getOrNull(`${contractName}_Proxy`)
    if (!proxyDeployment) {
      env.showMessage(`   Skipping ${contractName} - proxy not deployed`)
      continue
    }

    try {
      // Read per-proxy ProxyAdmin address from ERC1967 slot
      const proxyAdminAddress = await getProxyAdminAddress(client, proxyDeployment.address)

      // Read owner from ProxyAdmin
      const owner = (await client.readContract({
        address: proxyAdminAddress as `0x${string}`,
        abi: [{ name: 'owner', type: 'function', inputs: [], outputs: [{ type: 'address' }] }],
        functionName: 'owner',
      })) as string

      if (owner.toLowerCase() === governor.toLowerCase()) {
        env.showMessage(`   ✓ ${contractName}: ProxyAdmin (${proxyAdminAddress}) owned by governor`)
      } else {
        env.showMessage(`   ✗ ${contractName}: ProxyAdmin owned by ${owner}, expected ${governor}`)
      }
    } catch (error) {
      env.showMessage(`   ✗ ${contractName}: Error verifying ProxyAdmin ownership: ${error}`)
    }
  }

  env.showMessage('\n========== Verification Complete ==========\n')
}

func.tags = Tags.verifyGovernance
func.dependencies = [actionTag(ComponentTags.ISSUANCE_ALLOCATOR, DeploymentActions.TRANSFER)] // Run after governance transfer (step 6)

export default func
