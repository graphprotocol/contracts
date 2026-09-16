import { ACCESS_CONTROL_ENUMERABLE_ABI } from '@graphprotocol/deployment/lib/abis.js'
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { getGovernor } from '@graphprotocol/deployment/lib/controller-utils.js'
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
 * Transfer InnovationAllocation governance from deployer
 *
 * - Revoke GOVERNOR_ROLE from the deployment account
 * - Transfer ProxyAdmin ownership to the protocol governor
 *
 * Role grants happen in 04_configure.ts. The Foundation operator keeps only
 * OPERATOR_ROLE — it never holds GOVERNOR_ROLE or the ProxyAdmin.
 *
 * Refuses to revoke while the governor does not hold GOVERNOR_ROLE: that
 * combination would leave the contract with zero GOVERNOR_ROLE holders,
 * recoverable only by a proxy upgrade.
 *
 * Idempotent: checks on-chain state, skips if already transferred.
 *
 * Usage:
 *   pnpm hardhat deploy --tags InnovationAllocation,transfer --network <network>
 */
export default createActionModule(Contracts.issuance.InnovationAllocation, DeploymentActions.TRANSFER, async (env) => {
  const readFn = read(env)
  const executeFn = execute(env)
  const client = graph.getPublicClient(env) as PublicClient
  const deployer = requireDeployer(env)
  const governor = await getGovernor(env)
  const innovation = requireContract(env, Contracts.issuance.InnovationAllocation)

  env.showMessage(`\n========== Transfer ${Contracts.issuance.InnovationAllocation.name} ==========`)

  const precondition = await checkDeployerRevoked(client, innovation.address, deployer)
  if (precondition.done) {
    env.showMessage(`✓ Deployer GOVERNOR_ROLE already revoked`)
  } else {
    const GOVERNOR_ROLE = (await readFn(innovation, { functionName: 'GOVERNOR_ROLE' })) as `0x${string}`

    // Guard the irreversible step itself, so it holds however configure fell
    // short — a missing InnovationOperator entry, a partial run, a manual step.
    const governorHasRole = (await client.readContract({
      address: innovation.address as `0x${string}`,
      abi: ACCESS_CONTROL_ENUMERABLE_ABI,
      functionName: 'hasRole',
      args: [GOVERNOR_ROLE, governor as `0x${string}`],
    })) as boolean
    if (!governorHasRole) {
      env.showMessage(`\n❌ Governor ${governor} does not hold GOVERNOR_ROLE — refusing to revoke the deployer`)
      env.showMessage(`   Revoking now would leave ${Contracts.issuance.InnovationAllocation.name} with no`)
      env.showMessage(`   GOVERNOR_ROLE holder, recoverable only by a proxy upgrade.`)
      env.showMessage(`   Next: --tags InnovationAllocation,configure and re-run\n`)
      return
    }

    env.showMessage(`🔨 Revoking deployer GOVERNOR_ROLE...`)
    await executeFn(innovation, {
      account: deployer,
      functionName: 'revokeRole',
      args: [GOVERNOR_ROLE, deployer],
    })
    env.showMessage(`  ✓ revokeRole(GOVERNOR_ROLE) executed`)
  }

  await transferProxyAdminOwnership(env, Contracts.issuance.InnovationAllocation)

  env.showMessage(`\n✅ ${Contracts.issuance.InnovationAllocation.name} governance transferred!\n`)
})
