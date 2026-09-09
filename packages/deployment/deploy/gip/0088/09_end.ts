import {
  ISSUANCE_ALLOCATOR_ABI,
  PROVIDER_ELIGIBILITY_MANAGEMENT_ABI,
  REWARDS_MANAGER_ABI,
} from '@graphprotocol/deployment/lib/abis.js'
import {
  addressEquals,
  checkIssuanceConnectComplete,
  getRewardsManagerRawIssuanceRate,
  isRewardsManagerUpgraded,
} from '@graphprotocol/deployment/lib/contract-checks.js'
import {
  allocationTargetContract,
  Contracts,
  eligibilityOracleContract,
  type EligibilityOracleContractName,
} from '@graphprotocol/deployment/lib/contract-registry.js'
import {
  getResolvedSettingsForEnv,
  validateIssuanceAllocations,
} from '@graphprotocol/deployment/lib/deployment-config.js'
import { DeploymentActions, GoalTags, shouldSkipAction } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { formatGRT } from '@graphprotocol/deployment/lib/format.js'
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
 * - Eligibility: RM and RAM oracles match config (incl. none=unset), revertOnIneligible matches config
 * - Issuance: IA connected to RM, minter role granted, RAM allocation matches config
 *
 * Does NOT verify optional goals (issuance-close-guard).
 *
 * Usage:
 *   pnpm hardhat deploy --tags GIP-0088,all --network <network>
 */
const func: DeployScriptModule = async (env) => {
  if (shouldSkipAction(DeploymentActions.ALL)) return
  const settings = await getResolvedSettingsForEnv(env)
  const rmOracleName = settings.rewardsManager.eligibilityOracle
  const ramOracleName = settings.recurringAgreementManager.eligibilityOracle
  const configuredReoEntries = [rmOracleName, ramOracleName]
    .filter((n): n is EligibilityOracleContractName => n !== undefined)
    .map((n) => eligibilityOracleContract(n))
  await syncComponentsFromRegistry(env, [
    Contracts.issuance.IssuanceAllocator,
    Contracts.horizon.RewardsManager,
    Contracts.horizon.L2GraphToken,
    Contracts.issuance.RecurringAgreementManager,
    ...configuredReoEntries,
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

  // Verify IA activation state (issuance phase) — uses the strict end-state helper
  // so 09_end's "complete" verdict matches the issuance-connect idempotency gate.
  const connect = await checkIssuanceConnectComplete(
    client,
    issuanceAllocator.address,
    rewardsManager.address,
    graphToken.address,
  )

  if (!connect.iaIntegrated) failures.push('IA not integrated with RM')
  if (!connect.iaMinter) failures.push('IA missing minter role')
  if (!connect.ratesAligned)
    failures.push(`IA/RM rate mismatch: IA=${formatGRT(connect.iaRate)}, RM=${formatGRT(connect.rmRate)}`)
  if (!connect.rmAllocationShape)
    failures.push(
      `RM allocation shape wrong: self=${formatGRT(connect.rmAllocation.selfMintingRate)}, allocator=${formatGRT(connect.rmAllocation.allocatorMintingRate)} (expected self>0, allocator=0)`,
    )
  if (!connect.fullyAllocated)
    failures.push(`IA not 100% allocated: ${formatGRT(connect.iaTotalAllocationRate)} of ${formatGRT(connect.iaRate)}`)

  // Verify eligibility-oracle wiring (eligibility phase) — strict and symmetric
  // for RM and RAM: each target's on-chain oracle must match its config
  // (`<target>.eligibilityOracle`), and a target whose config names no oracle
  // must read back unset.
  const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'
  const verifyOracle = async (
    targetLabel: string,
    targetAddress: string,
    oracleName: EligibilityOracleContractName | undefined,
  ): Promise<void> => {
    let currentOracle: string
    try {
      currentOracle = (await client.readContract({
        address: targetAddress as `0x${string}`,
        abi: PROVIDER_ELIGIBILITY_MANAGEMENT_ABI,
        functionName: 'getProviderEligibilityOracle',
      })) as string
    } catch {
      failures.push(`${targetLabel} does not support getProviderEligibilityOracle (not upgraded?)`)
      return
    }
    if (oracleName) {
      const reo = env.getOrNull(oracleName)
      if (!reo) {
        failures.push(`${targetLabel}: configured oracle ${oracleName} not deployed`)
      } else if (!addressEquals(currentOracle, reo.address)) {
        failures.push(`${targetLabel} eligibility oracle is ${currentOracle}, expected ${oracleName} (${reo.address})`)
      }
    } else if (currentOracle !== ZERO_ADDRESS) {
      failures.push(`${targetLabel} eligibility oracle is ${currentOracle}, but config sets none (expected unset)`)
    }
  }
  await verifyOracle('RM', rewardsManager.address, rmOracleName)
  const ramForOracle = env.getOrNull(Contracts.issuance.RecurringAgreementManager.name)
  if (ramForOracle) {
    await verifyOracle('RAM', ramForOracle.address, ramOracleName)
  } else if (ramOracleName) {
    failures.push(`RAM configured with oracle ${ramOracleName} but RecurringAgreementManager not deployed`)
  }

  // Verify the issuance allocation table matches config (issuance-allocate goal).
  // validateIssuanceAllocations also re-checks the config total vs RM and the sum;
  // a config error surfaces as a single failure rather than aborting the gate.
  try {
    const rmIssuancePerBlock = await getRewardsManagerRawIssuanceRate(client, rewardsManager.address)
    for (const alloc of validateIssuanceAllocations(settings, rmIssuancePerBlock)) {
      const dep = env.getOrNull(allocationTargetContract(alloc.target).name)
      if (!dep) {
        failures.push(`Allocation configured for ${alloc.target} but it is not deployed`)
        continue
      }
      const onChain = (await client.readContract({
        address: issuanceAllocator.address as `0x${string}`,
        abi: ISSUANCE_ALLOCATOR_ABI,
        functionName: 'getTargetAllocation',
        args: [dep.address as `0x${string}`],
      })) as { totalAllocationRate: bigint; allocatorMintingRate: bigint; selfMintingRate: bigint }
      if (
        onChain.allocatorMintingRate !== alloc.allocatorMintingRate ||
        onChain.selfMintingRate !== alloc.selfMintingRate
      ) {
        failures.push(
          `${alloc.target} allocation mismatch: on-chain allocator=${formatGRT(onChain.allocatorMintingRate)}/self=${formatGRT(onChain.selfMintingRate)}, ` +
            `config allocator=${formatGRT(alloc.allocatorMintingRate)}/self=${formatGRT(alloc.selfMintingRate)}`,
        )
      }
    }
  } catch (err) {
    failures.push(err instanceof Error ? err.message : String(err))
  }

  // Verify revertOnIneligible matches config
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
