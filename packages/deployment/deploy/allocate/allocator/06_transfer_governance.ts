import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { getGovernor, getPauseGuardian } from '@graphprotocol/deployment/lib/controller-utils.js'
import { actionTag, ComponentTags, DeploymentActions, Tags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { requireContracts, requireDeployer } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { execute, read } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { DeployScriptModule } from '@rocketh/core/types'

/**
 * Transfer governance of ${Contracts.issuance.IssuanceAllocator.name} from deployer to protocol governor (deployer account)
 *
 * Step 6 from IssuanceAllocator.md:
 * - Grant PAUSE_ROLE to pause guardian (from Controller)
 * - Grant GOVERNOR_ROLE to protocol governor (from Controller.getGovernor())
 * - Revoke GOVERNOR_ROLE from deployment account (MUST grant to governance first, then revoke)
 *
 * This is a critical security step that transfers control from the deployment account
 * to the protocol governance multisig. After this step, only governance can modify
 * issuance allocations and rates.
 *
 * Requires deployer to have GOVERNOR_ROLE (granted during initialization in step 1).
 * Idempotent: checks on-chain state, skips if already transferred.
 *
 * Usage:
 *   pnpm hardhat deploy --tags issuance-transfer-governance --network <network>
 */
const func: DeployScriptModule = async (env) => {
  const readFn = read(env)
  const executeFn = execute(env)

  const deployer = requireDeployer(env)

  // Get protocol governor and pause guardian from Controller
  const governor = await getGovernor(env)
  const pauseGuardian = await getPauseGuardian(env)

  const [issuanceAllocator] = requireContracts(env, [Contracts.issuance.IssuanceAllocator])

  env.showMessage(`\n========== Transfer Governance of ${Contracts.issuance.IssuanceAllocator.name} ==========`)
  env.showMessage(`${Contracts.issuance.IssuanceAllocator.name}: ${issuanceAllocator.address}`)
  env.showMessage(`Deployer: ${deployer}`)
  env.showMessage(`Protocol Governor (from Controller): ${governor}`)
  env.showMessage(`Pause Guardian: ${pauseGuardian}\n`)

  // Get role constants
  const GOVERNOR_ROLE = (await readFn(issuanceAllocator, { functionName: 'GOVERNOR_ROLE' })) as `0x${string}`
  const PAUSE_ROLE = (await readFn(issuanceAllocator, { functionName: 'PAUSE_ROLE' })) as `0x${string}`

  // Check current state
  env.showMessage('📋 Checking current governance state...\n')

  const checks = {
    pauseRole: false,
    governorHasRole: false,
    deployerRevoked: false,
  }

  // Check pause role
  checks.pauseRole = (await readFn(issuanceAllocator, {
    functionName: 'hasRole',
    args: [PAUSE_ROLE, pauseGuardian],
  })) as boolean
  env.showMessage(`  Pause guardian has PAUSE_ROLE: ${checks.pauseRole ? '✓' : '✗'} (${pauseGuardian})`)

  // Check governor has GOVERNOR_ROLE
  checks.governorHasRole = (await readFn(issuanceAllocator, {
    functionName: 'hasRole',
    args: [GOVERNOR_ROLE, governor],
  })) as boolean
  env.showMessage(`  Governor has GOVERNOR_ROLE: ${checks.governorHasRole ? '✓' : '✗'} (${governor})`)

  // Check deployer no longer has GOVERNOR_ROLE
  const deployerHasRole = (await readFn(issuanceAllocator, {
    functionName: 'hasRole',
    args: [GOVERNOR_ROLE, deployer],
  })) as boolean
  checks.deployerRevoked = !deployerHasRole
  env.showMessage(`  Deployer GOVERNOR_ROLE revoked: ${checks.deployerRevoked ? '✓' : '✗'} (${deployer})`)

  // All checks passed?
  const allPassed = Object.values(checks).every(Boolean)
  if (allPassed) {
    env.showMessage(`\n✅ Governance already transferred to ${governor}\n`)
    return
  }

  // Execute governance transfer
  // CRITICAL: Must grant to governance BEFORE revoking from deployer
  env.showMessage('\n🔨 Executing governance transfer...\n')

  // Step 1: Grant PAUSE_ROLE to pause guardian
  if (!checks.pauseRole) {
    env.showMessage(`  Granting PAUSE_ROLE to ${pauseGuardian}...`)
    await executeFn(issuanceAllocator, {
      account: deployer,
      functionName: 'grantRole',
      args: [PAUSE_ROLE, pauseGuardian],
    })
    env.showMessage('  ✓ grantRole(PAUSE_ROLE) executed')
  }

  // Step 2: Grant GOVERNOR_ROLE to governor
  if (!checks.governorHasRole) {
    env.showMessage(`  Granting GOVERNOR_ROLE to ${governor}...`)
    await executeFn(issuanceAllocator, {
      account: deployer,
      functionName: 'grantRole',
      args: [GOVERNOR_ROLE, governor],
    })
    env.showMessage('  ✓ grantRole(GOVERNOR_ROLE) executed')
  }

  // Step 3: Revoke GOVERNOR_ROLE from deployer (ONLY after governance has the role)
  if (!checks.deployerRevoked) {
    env.showMessage(`  Revoking GOVERNOR_ROLE from deployer ${deployer}...`)
    await executeFn(issuanceAllocator, {
      account: deployer,
      functionName: 'revokeRole',
      args: [GOVERNOR_ROLE, deployer],
    })
    env.showMessage('  ✓ revokeRole(GOVERNOR_ROLE) executed')
  }

  env.showMessage(`\n✅ Governance transferred to ${governor}!\n`)
  env.showMessage(
    `⚠️  IMPORTANT: Deployer no longer has control. Only governance can modify ${Contracts.issuance.IssuanceAllocator.name}.\n`,
  )
}

func.tags = Tags.issuanceTransfer
func.dependencies = [actionTag(ComponentTags.ISSUANCE_ALLOCATOR, DeploymentActions.CONFIGURE)]

export default func
