import { ISSUANCE_ALLOCATOR_ABI } from '@graphprotocol/deployment/lib/abis.js'
import { getTargetChainIdFromEnv } from '@graphprotocol/deployment/lib/address-book-utils.js'
import {
  addressEquals,
  checkOperatorRole,
  getRewardsManagerRawIssuanceRate,
} from '@graphprotocol/deployment/lib/contract-checks.js'
import { allocationTargetContract, Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { getGovernor, getPauseGuardian } from '@graphprotocol/deployment/lib/controller-utils.js'
import { getOnChainImplementation } from '@graphprotocol/deployment/lib/deploy-implementation.js'
import {
  getResolvedSettingsForEnv,
  validateIssuanceAllocations,
} from '@graphprotocol/deployment/lib/deployment-config.js'
import { DeploymentActions, GoalTags, shouldSkipAction } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { formatGRT } from '@graphprotocol/deployment/lib/format.js'
import {
  getDeployer,
  getProxyAdminAddress,
  requireContracts,
} from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import {
  checkDeployerRevoked,
  checkInnovationAllocationConfigured,
  checkProxyAdminTransferred,
} from '@graphprotocol/deployment/lib/preconditions.js'
import { syncComponentsFromRegistry } from '@graphprotocol/deployment/lib/sync-utils.js'
import { graph } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { DeployScriptModule } from '@rocketh/core/types'
import type { PublicClient } from 'viem'

/**
 * GIP-0089,all — Full innovation allocation verification
 *
 * Verifies the contract is deployed with correct role assignment and that the
 * IssuanceAllocator table matches config, including that total issuance is unchanged.
 *
 * Usage:
 *   pnpm hardhat deploy --tags GIP-0089,all --network <network>
 */
const func: DeployScriptModule = async (env) => {
  if (shouldSkipAction(DeploymentActions.ALL)) return

  await syncComponentsFromRegistry(env, [
    Contracts.issuance.IssuanceAllocator,
    Contracts.horizon.RewardsManager,
    Contracts.issuance.InnovationAllocation,
    Contracts.issuance.DirectAllocation_Implementation,
  ])

  const [issuanceAllocator, rewardsManager, innovation] = requireContracts(env, [
    Contracts.issuance.IssuanceAllocator,
    Contracts.horizon.RewardsManager,
    Contracts.issuance.InnovationAllocation,
  ])

  const client = graph.getPublicClient(env) as PublicClient
  const governor = await getGovernor(env)
  const pauseGuardian = await getPauseGuardian(env)
  const settings = await getResolvedSettingsForEnv(env)
  const failures: string[] = []

  const targetChainId = await getTargetChainIdFromEnv(env)
  const issuanceBook = graph.getIssuanceAddressBook(targetChainId)
  const operator = issuanceBook.entryExists('InnovationOperator')
    ? (issuanceBook.getEntry('InnovationOperator')?.address ?? null)
    : null

  // Roles: governor, pause guardian, operator
  if (!operator) {
    failures.push('InnovationOperator not configured in the issuance address book')
  } else {
    const configured = await checkInnovationAllocationConfigured(
      client,
      innovation.address,
      governor,
      pauseGuardian,
      operator,
    )
    if (!configured.done) failures.push(`InnovationAllocation roles: ${configured.reason}`)
  }

  // OPERATOR_ROLE exclusivity — an extra holder can call sendTokens and drain it.
  // Wrapped: a read fault must land as a gate failure line, not a stack trace.
  try {
    const operatorCheck = await checkOperatorRole(client, innovation.address, operator, 'InnovationOperator')
    if (!operatorCheck.ok) failures.push(`InnovationAllocation ${operatorCheck.message}`)
  } catch (err) {
    failures.push(
      `InnovationAllocation OPERATOR_ROLE check failed: ${err instanceof Error ? err.message : String(err)}`,
    )
  }

  // Deployer must no longer hold GOVERNOR_ROLE.
  // getDeployer filters the dummy status-run key, so this skips rather than
  // asserting against an address that was never the real deployer.
  const deployer = getDeployer(env)
  if (deployer) {
    const revoked = await checkDeployerRevoked(client, innovation.address, deployer)
    if (!revoked.done) failures.push(`InnovationAllocation: ${revoked.reason}`)
  }

  // The proxy must sit on the shared DirectAllocation implementation. A drifted
  // artifact would have redeployed the implementation and split this proxy off
  // from DefaultAllocation / ReclaimedRewards.
  const sharedImpl = env.getOrNull(Contracts.issuance.DirectAllocation_Implementation.name)
  if (!sharedImpl) {
    failures.push(`${Contracts.issuance.DirectAllocation_Implementation.name} not recorded in the address book`)
  } else {
    try {
      const onChainImpl = await getOnChainImplementation(client, innovation.address, 'transparent')
      if (!addressEquals(onChainImpl, sharedImpl.address)) {
        failures.push(
          `InnovationAllocation implementation is ${onChainImpl}, expected the shared ` +
            `${Contracts.issuance.DirectAllocation_Implementation.name} (${sharedImpl.address})`,
        )
      }
    } catch (err) {
      failures.push(
        `InnovationAllocation implementation read failed: ${err instanceof Error ? err.message : String(err)}`,
      )
    }
  }

  // ProxyAdmin must be owned by the protocol governor (governance-transferred).
  try {
    const proxyAdmin = await getProxyAdminAddress(client, innovation.address)
    const transferred = await checkProxyAdminTransferred(client, proxyAdmin, governor)
    if (!transferred.done) failures.push(`InnovationAllocation ProxyAdmin: ${transferred.reason}`)
  } catch (err) {
    failures.push(`InnovationAllocation ProxyAdmin check failed: ${err instanceof Error ? err.message : String(err)}`)
  }

  // Allocation table matches config, and the config total still matches RM's raw rate
  try {
    const rmIssuancePerBlock = await getRewardsManagerRawIssuanceRate(client, rewardsManager.address)
    env.showMessage(`\nRM raw issuancePerBlock: ${formatGRT(rmIssuancePerBlock)} (must be unchanged)`)
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
      const ok =
        onChain.allocatorMintingRate === alloc.allocatorMintingRate && onChain.selfMintingRate === alloc.selfMintingRate
      env.showMessage(
        `  ${ok ? '✓' : '✗'} ${alloc.target}: allocator=${formatGRT(onChain.allocatorMintingRate)}, self=${formatGRT(onChain.selfMintingRate)}`,
      )
      if (!ok) {
        failures.push(
          `${alloc.target} allocation mismatch: on-chain allocator=${formatGRT(onChain.allocatorMintingRate)}/self=${formatGRT(onChain.selfMintingRate)}, ` +
            `config allocator=${formatGRT(alloc.allocatorMintingRate)}/self=${formatGRT(alloc.selfMintingRate)}`,
        )
      }
    }

    // Per-target matching cannot see a stale allocation on a target that is absent
    // from the config table, so assert the 100% invariant directly (as GIP-0088 does).
    const iaRate = (await client.readContract({
      address: issuanceAllocator.address as `0x${string}`,
      abi: ISSUANCE_ALLOCATOR_ABI,
      functionName: 'getIssuancePerBlock',
    })) as bigint
    const total = (await client.readContract({
      address: issuanceAllocator.address as `0x${string}`,
      abi: ISSUANCE_ALLOCATOR_ABI,
      functionName: 'getTotalAllocation',
    })) as { totalAllocationRate: bigint; allocatorMintingRate: bigint; selfMintingRate: bigint }
    const fullyAllocated = iaRate > 0n && total.totalAllocationRate === iaRate
    env.showMessage(
      `  ${fullyAllocated ? '✓' : '✗'} IA fully allocated: ${formatGRT(total.totalAllocationRate)} of ${formatGRT(iaRate)}`,
    )
    if (!fullyAllocated) {
      failures.push(`IA not 100% allocated: ${formatGRT(total.totalAllocationRate)} of ${formatGRT(iaRate)}`)
    }
  } catch (err) {
    failures.push(err instanceof Error ? err.message : String(err))
  }

  if (failures.length > 0) {
    env.showMessage(`\n❌ GIP-0089 incomplete:`)
    for (const f of failures) env.showMessage(`   - ${f}`)
    env.showMessage('')
    process.exit(1)
  }

  env.showMessage(`\n✅ GIP-0089 complete: innovation allocation deployed, configured, and funded\n`)
}

func.tags = [GoalTags.GIP_0089]
func.dependencies = [GoalTags.GIP_0089_ALLOCATE]
func.skip = async () => shouldSkipAction(DeploymentActions.ALL)

export default func
