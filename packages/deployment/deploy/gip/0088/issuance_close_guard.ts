import { SUBGRAPH_SERVICE_CLOSE_GUARD_ABI } from '@graphprotocol/deployment/lib/abis.js'
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { canSignAsGovernor } from '@graphprotocol/deployment/lib/controller-utils.js'
import { getResolvedSettingsForEnv } from '@graphprotocol/deployment/lib/deployment-config.js'
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
 * GIP-0088:issuance-close-guard — Set the SubgraphService close-guard switch
 *
 * Optional governance TX:
 *   `SS.setBlockClosingAllocationWithActiveAgreement(<configured>)`
 * Desired value comes from
 * `SubgraphService.blockClosingAllocationWithActiveAgreement` in
 * `config/<network>.json5` (default `true`).
 *
 * Not activated by `all` — requires explicit `--tags GIP-0088:issuance-close-guard`.
 *
 * Idempotent: reads on-chain state, skips if it already matches the desired value.
 *
 * Usage:
 *   pnpm hardhat deploy --tags GIP-0088:issuance-close-guard --network <network>
 */
const func: DeployScriptModule = async (env) => {
  if (shouldSkipOptionalGoal(GoalTags.GIP_0088_ISSUANCE_CLOSE_GUARD)) return
  await syncComponentsFromRegistry(env, [Contracts['subgraph-service'].SubgraphService])

  const client = graph.getPublicClient(env) as PublicClient
  const ss = requireContract(env, Contracts['subgraph-service'].SubgraphService)
  const settings = await getResolvedSettingsForEnv(env)
  const desired = settings.subgraphService.blockClosingAllocationWithActiveAgreement

  env.showMessage(`\n========== GIP-0088: Issuance Close Guard ==========`)
  env.showMessage(`${Contracts['subgraph-service'].SubgraphService.name}: ${ss.address}`)

  // Check current state
  env.showMessage('\n📋 Checking current configuration...\n')

  const enabled = (await client.readContract({
    address: ss.address as `0x${string}`,
    abi: SUBGRAPH_SERVICE_CLOSE_GUARD_ABI,
    functionName: 'getBlockClosingAllocationWithActiveAgreement',
  })) as boolean
  env.showMessage(`  blockClosingAllocationWithActiveAgreement: ${enabled} (desired: ${desired})`)

  if (enabled === desired) {
    env.showMessage(
      `\n✅ ${Contracts['subgraph-service'].SubgraphService.name} close guard already at desired state (${desired})\n`,
    )
    return
  }

  const { governor, canSign } = await canSignAsGovernor(env)

  env.showMessage('\n🔨 Building configuration TX batch...\n')

  const builder = await createGovernanceTxBuilder(env, `gip-0088-issuance-close-guard`)

  const data = encodeFunctionData({
    abi: SUBGRAPH_SERVICE_CLOSE_GUARD_ABI,
    functionName: 'setBlockClosingAllocationWithActiveAgreement',
    args: [desired],
  })
  builder.addTx({ to: ss.address, value: '0', data })
  env.showMessage(`  + setBlockClosingAllocationWithActiveAgreement(${desired})`)

  if (canSign) {
    env.showMessage('\n🔨 Executing configuration TX batch...\n')
    await executeTxBatchDirect(env, builder, governor)
    env.showMessage(`\n✅ GIP-0088: allocation close guard set to ${desired}\n`)
  } else {
    saveGovernanceTx(env, builder, `GIP-0088: allocation close guard`)
  }
}

func.tags = [GoalTags.GIP_0088_ISSUANCE_CLOSE_GUARD]
func.dependencies = [ComponentTags.SUBGRAPH_SERVICE]
func.skip = async () => shouldSkipOptionalGoal(GoalTags.GIP_0088_ISSUANCE_CLOSE_GUARD)

export default func
