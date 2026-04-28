import { REWARDS_MANAGER_ABI } from '@graphprotocol/deployment/lib/abis.js'
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { canSignAsGovernor } from '@graphprotocol/deployment/lib/controller-utils.js'
import { loadDeploymentConfig } from '@graphprotocol/deployment/lib/deployment-config.js'
import { ComponentTags, GoalTags, shouldSkipOptionalGoal } from '@graphprotocol/deployment/lib/deployment-tags.js'
import {
  createGovernanceTxBuilder,
  executeTxBatchDirect,
  saveGovernanceTx,
} from '@graphprotocol/deployment/lib/execute-governance.js'
import { requireContract } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { syncComponentsFromRegistry } from '@graphprotocol/deployment/lib/sync-utils.js'
import { graph } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { DeployScriptModule } from '@rocketh/core/types'
import type { PublicClient } from 'viem'
import { encodeFunctionData } from 'viem'

/**
 * GIP-0088:eligibility-revert — Configure RM revert-on-ineligible behaviour
 *
 * Optional governance TX: RM.setRevertOnIneligible(<config>)
 *
 * Reads `RewardsManager.revertOnIneligible` from config/<network>.json5,
 * defaulting to `true` (the expected target for all deployments).
 *
 * Not activated by `all` — requires explicit `--tags GIP-0088:eligibility-revert`.
 *
 * Idempotent: skips if on-chain state already matches config.
 *
 * Usage:
 *   pnpm hardhat deploy --tags GIP-0088:eligibility-revert --network <network>
 */
const func: DeployScriptModule = async (env) => {
  if (shouldSkipOptionalGoal(GoalTags.GIP_0088_ELIGIBILITY_REVERT)) return
  await syncComponentsFromRegistry(env, [Contracts.horizon.RewardsManager])

  const client = graph.getPublicClient(env) as PublicClient
  const rm = requireContract(env, Contracts.horizon.RewardsManager)

  env.showMessage(`\n========== GIP-0088: Eligibility Revert ==========`)
  env.showMessage(`${Contracts.horizon.RewardsManager.name}: ${rm.address}`)

  const config = await loadDeploymentConfig(env)
  const desired = config.RewardsManager?.revertOnIneligible ?? true

  // Check current state
  env.showMessage('\n📋 Checking current configuration...\n')
  env.showMessage(`  Config: revertOnIneligible = ${desired}`)

  let revertOnIneligible: boolean
  try {
    revertOnIneligible = (await client.readContract({
      address: rm.address as `0x${string}`,
      abi: REWARDS_MANAGER_ABI,
      functionName: 'getRevertOnIneligible',
    })) as boolean
  } catch {
    // Function not available — RM not upgraded, skip (matches eligibility_integrate)
    env.showMessage(
      `\n  ○ ${Contracts.horizon.RewardsManager.name} does not support getRevertOnIneligible — skipping\n`,
    )
    return
  }
  env.showMessage(
    `  On-chain: revertOnIneligible = ${revertOnIneligible} ${revertOnIneligible === desired ? '✓' : '✗'}`,
  )

  if (revertOnIneligible === desired) {
    env.showMessage(`\n✅ ${Contracts.horizon.RewardsManager.name} already matches config\n`)
    return
  }

  const { governor, canSign } = await canSignAsGovernor(env)

  env.showMessage('\n🔨 Building configuration TX batch...\n')

  const builder = await createGovernanceTxBuilder(env, `gip-0088-eligibility-revert`)

  const data = encodeFunctionData({
    abi: REWARDS_MANAGER_ABI,
    functionName: 'setRevertOnIneligible',
    args: [desired],
  })
  builder.addTx({ to: rm.address, value: '0', data })
  env.showMessage(`  + setRevertOnIneligible(${desired})`)

  if (canSign) {
    env.showMessage('\n🔨 Executing configuration TX batch...\n')
    await executeTxBatchDirect(env, builder, governor)
    env.showMessage(`\n✅ GIP-0088: revertOnIneligible set to ${desired}\n`)
  } else {
    saveGovernanceTx(env, builder, `GIP-0088: revertOnIneligible`)
  }
}

func.tags = [GoalTags.GIP_0088_ELIGIBILITY_REVERT]
func.dependencies = [ComponentTags.REWARDS_MANAGER]
func.skip = async () => shouldSkipOptionalGoal(GoalTags.GIP_0088_ELIGIBILITY_REVERT)

export default func
