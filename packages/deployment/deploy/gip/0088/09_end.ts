import { PROVIDER_ELIGIBILITY_MANAGEMENT_ABI, REWARDS_MANAGER_ABI } from '@graphprotocol/deployment/lib/abis.js'
import {
  addressEquals,
  checkIssuanceAllocatorActivation,
  isRewardsManagerUpgraded,
} from '@graphprotocol/deployment/lib/contract-checks.js'
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { getResolvedSettingsForEnv } from '@graphprotocol/deployment/lib/deployment-config.js'
import { DeploymentActions, GoalTags, shouldSkipAction } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { requireContracts } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { syncComponentsFromRegistry } from '@graphprotocol/deployment/lib/sync-utils.js'
import { graph } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { DeployScriptModule } from '@rocketh/core/types'
import type { PublicClient } from 'viem'

/**
 * GIP-0088,all — Full GIP-0088 deployment verification
 *
 * Verifies all non-optional phases are complete:
 * - Upgrade: RM upgraded (supports IIssuanceTarget)
 * - Eligibility: REO integrated with RM, revertOnIneligible matches config
 * - Issuance: IA connected to RM, minter role granted
 *
 * Does NOT verify optional goals (issuance-close-guard).
 *
 * Usage:
 *   pnpm hardhat deploy --tags GIP-0088,all --network <network>
 */
const func: DeployScriptModule = async (env) => {
  if (shouldSkipAction(DeploymentActions.ALL)) return
  await syncComponentsFromRegistry(env, [
    Contracts.issuance.IssuanceAllocator,
    Contracts.horizon.RewardsManager,
    Contracts.horizon.L2GraphToken,
    Contracts.issuance.RewardsEligibilityOracleA,
  ])
  const [issuanceAllocator, rewardsManager, graphToken] = requireContracts(env, [
    Contracts.issuance.IssuanceAllocator,
    Contracts.horizon.RewardsManager,
    Contracts.horizon.L2GraphToken,
  ])

  const client = graph.getPublicClient(env) as PublicClient
  const failures: string[] = []

  // Verify RM has been upgraded (supports IERC165)
  const upgraded = await isRewardsManagerUpgraded(client, rewardsManager.address)
  if (!upgraded) {
    env.showMessage(`\n❌ ${Contracts.horizon.RewardsManager.name} not upgraded - run GIP-0088:upgrade,upgrade first\n`)
    process.exit(1)
  }

  // Verify IA activation state (issuance phase)
  const activation = await checkIssuanceAllocatorActivation(
    client,
    issuanceAllocator.address,
    rewardsManager.address,
    graphToken.address,
  )

  if (!activation.iaIntegrated) failures.push('IA not integrated with RM')
  if (!activation.iaMinter) failures.push('IA missing minter role')

  // Verify REO integration (eligibility phase)
  const reo = env.getOrNull(Contracts.issuance.RewardsEligibilityOracleA.name)
  if (reo) {
    const currentOracle = (await client.readContract({
      address: rewardsManager.address as `0x${string}`,
      abi: PROVIDER_ELIGIBILITY_MANAGEMENT_ABI,
      functionName: 'getProviderEligibilityOracle',
    })) as string
    if (!addressEquals(currentOracle, reo.address)) {
      failures.push('REO not integrated with RM')
    }
  } else {
    failures.push('RewardsEligibilityOracleA not deployed')
  }

  // Verify revertOnIneligible matches config
  const settings = await getResolvedSettingsForEnv(env)
  const desiredRevert = settings.rewardsManager.revertOnIneligible
  try {
    const onChainRevert = (await client.readContract({
      address: rewardsManager.address as `0x${string}`,
      abi: REWARDS_MANAGER_ABI,
      functionName: 'getRevertOnIneligible',
    })) as boolean
    if (onChainRevert !== desiredRevert) {
      failures.push(`revertOnIneligible mismatch: on-chain=${onChainRevert}, config=${desiredRevert}`)
    }
  } catch {
    failures.push('RM does not support getRevertOnIneligible (not upgraded?)')
  }

  if (failures.length > 0) {
    env.showMessage(`\n❌ GIP-0088 incomplete:`)
    for (const f of failures) env.showMessage(`   - ${f}`)
    env.showMessage('')
    process.exit(1)
  }

  env.showMessage(`\n✅ GIP-0088 complete: all contracts deployed, upgraded, and configured\n`)
}

func.tags = [GoalTags.GIP_0088]
func.dependencies = [
  GoalTags.GIP_0088_UPGRADE,
  GoalTags.GIP_0088_ELIGIBILITY_INTEGRATE,
  GoalTags.GIP_0088_ISSUANCE_CONNECT,
  GoalTags.GIP_0088_ISSUANCE_ALLOCATE,
]
func.skip = async () => shouldSkipAction(DeploymentActions.ALL)

export default func
