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
 * Transfer DefaultAllocation governance from deployer
 *
 * - Revoke GOVERNOR_ROLE from deployment account
 * - Transfer ProxyAdmin ownership to governor
 *
 * Role grants happen in 04_configure.ts.
 *
 * Usage:
 *   pnpm hardhat deploy --tags DefaultAllocation,transfer --network <network>
 */
export default createActionModule(Contracts.issuance.DefaultAllocation, DeploymentActions.TRANSFER, async (env) => {
  const readFn = read(env)
  const executeFn = execute(env)
  const client = graph.getPublicClient(env) as PublicClient
  const deployer = requireDeployer(env)
  const da = requireContract(env, Contracts.issuance.DefaultAllocation)

  env.showMessage(`\n========== Transfer ${Contracts.issuance.DefaultAllocation.name} ==========`)

  const precondition = await checkDeployerRevoked(client, da.address, deployer)
  if (precondition.done) {
    env.showMessage(`✓ Deployer GOVERNOR_ROLE already revoked`)
  } else {
    const GOVERNOR_ROLE = (await readFn(da, { functionName: 'GOVERNOR_ROLE' })) as `0x${string}`

    env.showMessage(`🔨 Revoking deployer GOVERNOR_ROLE...`)
    await executeFn(da, {
      account: deployer,
      functionName: 'revokeRole',
      args: [GOVERNOR_ROLE, deployer],
    })
    env.showMessage(`  ✓ revokeRole(GOVERNOR_ROLE) executed`)
  }

  await transferProxyAdminOwnership(env, Contracts.issuance.DefaultAllocation)

  env.showMessage(`\n✅ ${Contracts.issuance.DefaultAllocation.name} governance transferred!\n`)
})
