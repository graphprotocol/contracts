import { ISSUANCE_ALLOCATOR_ABI } from '@graphprotocol/deployment/lib/abis.js'
import { getTargetChainIdFromEnv } from '@graphprotocol/deployment/lib/address-book-utils.js'
import { checkOperatorRole, getRewardsManagerRawIssuanceRate } from '@graphprotocol/deployment/lib/contract-checks.js'
import {
  allocationTargetContract,
  Contracts,
  type RegistryEntry,
} from '@graphprotocol/deployment/lib/contract-registry.js'
import { getResolvedSettingsForEnv } from '@graphprotocol/deployment/lib/deployment-config.js'
import { GoalTags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { formatGRT } from '@graphprotocol/deployment/lib/format.js'
import { createStatusModule } from '@graphprotocol/deployment/lib/script-factories.js'
import { syncComponentsFromRegistry } from '@graphprotocol/deployment/lib/sync-utils.js'
import { graph } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { PublicClient } from 'viem'

/**
 * GIP-0089 status — read-only view of the innovation allocation rollout.
 *
 * Usage:
 *   pnpm hardhat deploy --tags GIP-0089 --network <network>
 */
export default createStatusModule(GoalTags.GIP_0089, async (env) => {
  const targetChainId = await getTargetChainIdFromEnv(env)
  const settings = await getResolvedSettingsForEnv(env)

  // Sync the contracts this status touches via env.getOrNull so the read paths
  // work without depending on a separate global sync run. deployments/ is
  // gitignored and createStatusModule declares no dependencies, so without this
  // a fresh checkout reports "not deployed" for contracts that are live.
  const toSync = new Map<string, RegistryEntry>()
  for (const entry of [
    Contracts.issuance.InnovationAllocation,
    Contracts.issuance.IssuanceAllocator,
    Contracts.horizon.RewardsManager,
    ...settings.issuanceAllocator.allocations.map((alloc) => allocationTargetContract(alloc.target)),
  ]) {
    toSync.set(entry.name, entry)
  }
  await syncComponentsFromRegistry(env, [...toSync.values()])

  const client = graph.getPublicClient(env) as PublicClient
  const issuanceBook = graph.getIssuanceAddressBook(targetChainId)

  env.showMessage(`\n========== GIP-0089: Innovation Allocation ==========\n`)

  const innovation = env.getOrNull(Contracts.issuance.InnovationAllocation.name)
  if (!innovation) {
    env.showMessage(`  ✗ ${Contracts.issuance.InnovationAllocation.name} not deployed`)
    env.showMessage(`\n  Next: pnpm hardhat deploy --tags InnovationAllocation,deploy --network ${env.name}\n`)
    return
  }
  env.showMessage(`  ✓ InnovationAllocation: ${innovation.address}`)

  const operator = issuanceBook.entryExists('InnovationOperator')
    ? (issuanceBook.getEntry('InnovationOperator')?.address ?? null)
    : null
  const operatorCheck = await checkOperatorRole(client, innovation.address, operator, 'InnovationOperator')
  env.showMessage(`  ${operatorCheck.ok ? '✓' : '✗'} ${operatorCheck.message}`)

  const ia = env.getOrNull(Contracts.issuance.IssuanceAllocator.name)
  const rm = env.getOrNull(Contracts.horizon.RewardsManager.name)
  if (!ia || !rm) {
    env.showMessage(`\n  ○ IssuanceAllocator or RewardsManager not available — skipping allocation view\n`)
    return
  }

  const rmRate = await getRewardsManagerRawIssuanceRate(client, rm.address)
  env.showMessage(`\n  RM raw issuancePerBlock: ${formatGRT(rmRate)}`)

  for (const alloc of settings.issuanceAllocator.allocations) {
    const dep = env.getOrNull(allocationTargetContract(alloc.target).name)
    if (!dep) {
      env.showMessage(`  ○ ${alloc.target}: not deployed`)
      continue
    }
    const onChain = (await client.readContract({
      address: ia.address as `0x${string}`,
      abi: ISSUANCE_ALLOCATOR_ABI,
      functionName: 'getTargetAllocation',
      args: [dep.address as `0x${string}`],
    })) as { totalAllocationRate: bigint; allocatorMintingRate: bigint; selfMintingRate: bigint }
    env.showMessage(
      `  ${alloc.target}: allocator=${formatGRT(onChain.allocatorMintingRate)}, self=${formatGRT(onChain.selfMintingRate)} ` +
        `(config allocator=${alloc.allocatorGrtPerBlock}, self=${alloc.selfGrtPerBlock})`,
    )
  }
  env.showMessage('')
})
