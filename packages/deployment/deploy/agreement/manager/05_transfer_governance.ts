import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { DeploymentActions } from '@graphprotocol/deployment/lib/deployment-tags.js'
import {
  requireContract,
  requireDeployer,
  transferProxyAdminOwnership,
} from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { checkDeployerRevoked } from '@graphprotocol/deployment/lib/preconditions.js'
import { createActionModule } from '@graphprotocol/deployment/lib/script-factories.js'
import { execute, graph, read } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { PublicClient } from 'viem'

/**
 * Transfer RecurringAgreementManager governance from deployer
 *
 * - Revoke GOVERNOR_ROLE from deployment account
 * - Transfer ProxyAdmin ownership to governor
 *
 * Role grants (GOVERNOR_ROLE, PAUSE_ROLE, COLLECTOR_ROLE, DATA_SERVICE_ROLE)
 * happen in 04_configure.ts. This script only revokes deployer access.
 *
 * Idempotent: checks on-chain state, skips if already transferred.
 *
 * Usage:
 *   pnpm hardhat deploy --tags RecurringAgreementManager,transfer --network <network>
 */
export default createActionModule(
  Contracts.issuance.RecurringAgreementManager,
  DeploymentActions.TRANSFER,
  async (env) => {
    const readFn = read(env)
    const executeFn = execute(env)
    const client = graph.getPublicClient(env) as PublicClient
    const deployer = requireDeployer(env)
    const ram = requireContract(env, Contracts.issuance.RecurringAgreementManager)

    env.showMessage(`\n========== Transfer ${Contracts.issuance.RecurringAgreementManager.name} ==========`)

    // Check if deployer GOVERNOR_ROLE already revoked (shared precondition check)
    const precondition = await checkDeployerRevoked(client, ram.address, deployer)
    if (precondition.done) {
      env.showMessage(`✓ Deployer GOVERNOR_ROLE already revoked`)
    } else {
      const GOVERNOR_ROLE = (await readFn(ram, { functionName: 'GOVERNOR_ROLE' })) as `0x${string}`

      env.showMessage(`🔨 Revoking deployer GOVERNOR_ROLE...`)
      await executeFn(ram, {
        account: deployer,
        functionName: 'revokeRole',
        args: [GOVERNOR_ROLE, deployer],
      })
      env.showMessage(`  ✓ revokeRole(GOVERNOR_ROLE) executed`)
    }

    // Transfer ProxyAdmin ownership to governor
    await transferProxyAdminOwnership(env, Contracts.issuance.RecurringAgreementManager)

    env.showMessage(`\n✅ ${Contracts.issuance.RecurringAgreementManager.name} governance transferred!\n`)
  },
)
