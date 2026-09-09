import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { getGovernor } from '@graphprotocol/deployment/lib/controller-utils.js'
import { DeploymentActions } from '@graphprotocol/deployment/lib/deployment-tags.js'
import {
  requireContracts,
  requireDeployer,
  transferProxyAdminOwnership,
} from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { checkDeployerRevoked } from '@graphprotocol/deployment/lib/preconditions.js'
import { createActionModule } from '@graphprotocol/deployment/lib/script-factories.js'
import { execute, graph, read } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { PublicClient } from 'viem'

/**
 * Transfer IssuanceAllocator governance from deployer to protocol governor
 *
 * - Revoke GOVERNOR_ROLE from deployment account
 * - Transfer ProxyAdmin ownership to governor
 *
 * Role grants (GOVERNOR_ROLE to governor, PAUSE_ROLE to pauseGuardian) happen
 * in 04_configure.ts. This script only revokes deployer access.
 *
 * Idempotent: checks on-chain state, skips if already transferred.
 *
 * Usage:
 *   pnpm hardhat deploy --tags IssuanceAllocator,transfer --network <network>
 */
export default createActionModule(Contracts.issuance.IssuanceAllocator, DeploymentActions.TRANSFER, async (env) => {
  const readFn = read(env)
  const executeFn = execute(env)
  const client = graph.getPublicClient(env) as PublicClient

  const deployer = requireDeployer(env)
  const governor = await getGovernor(env)
  const [issuanceAllocator] = requireContracts(env, [Contracts.issuance.IssuanceAllocator])

  env.showMessage(`\n========== Transfer ${Contracts.issuance.IssuanceAllocator.name} ==========`)
  env.showMessage(`Deployer: ${deployer}`)
  env.showMessage(`Governor: ${governor}\n`)

  // Check if deployer GOVERNOR_ROLE already revoked (shared precondition check)
  const precondition = await checkDeployerRevoked(client, issuanceAllocator.address, deployer)
  if (precondition.done) {
    env.showMessage(`✓ Deployer GOVERNOR_ROLE already revoked`)
  } else {
    const GOVERNOR_ROLE = (await readFn(issuanceAllocator, { functionName: 'GOVERNOR_ROLE' })) as `0x${string}`

    env.showMessage(`🔨 Revoking deployer GOVERNOR_ROLE...`)
    await executeFn(issuanceAllocator, {
      account: deployer,
      functionName: 'revokeRole',
      args: [GOVERNOR_ROLE, deployer],
    })
    env.showMessage(`  ✓ revokeRole(GOVERNOR_ROLE) executed`)
  }

  // Transfer ProxyAdmin ownership to governor
  await transferProxyAdminOwnership(env, Contracts.issuance.IssuanceAllocator)

  env.showMessage(`\n✅ ${Contracts.issuance.IssuanceAllocator.name} governance transferred!\n`)
})
