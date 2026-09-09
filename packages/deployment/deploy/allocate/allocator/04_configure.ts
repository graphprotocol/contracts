import { ACCESS_CONTROL_ENUMERABLE_ABI, REWARDS_MANAGER_DEPRECATED_ABI } from '@graphprotocol/deployment/lib/abis.js'
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { getGovernor, getPauseGuardian } from '@graphprotocol/deployment/lib/controller-utils.js'
import { ComponentTags, DeploymentActions } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { requireContracts, requireDeployer } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { checkIAConfigured } from '@graphprotocol/deployment/lib/preconditions.js'
import { createActionModule } from '@graphprotocol/deployment/lib/script-factories.js'
import { graph, read, tx } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { PublicClient } from 'viem'
import { encodeFunctionData } from 'viem'

/**
 * Configure IssuanceAllocator
 *
 * - Sets issuance rate to match RewardsManager
 * - Configures RM as 100% self-minting target
 * - Grants GOVERNOR_ROLE to protocol governor
 * - Grants PAUSE_ROLE to pause guardian
 *
 * If deployer has GOVERNOR_ROLE (fresh deploy), executes directly.
 * If governance transferred, generates governance TX or executes via governor.
 *
 * Idempotent: checks on-chain state, skips if already configured.
 *
 * Usage:
 *   pnpm hardhat deploy --tags IssuanceAllocator,configure --network <network>
 */
export default createActionModule(
  Contracts.issuance.IssuanceAllocator,
  DeploymentActions.CONFIGURE,
  async (env) => {
    const readFn = read(env)
    const deployer = requireDeployer(env)
    const governor = await getGovernor(env)
    const pauseGuardian = await getPauseGuardian(env)

    const [issuanceAllocator, rewardsManager] = requireContracts(env, [
      Contracts.issuance.IssuanceAllocator,
      Contracts.horizon.RewardsManager,
    ])

    const client = graph.getPublicClient(env) as PublicClient

    env.showMessage(`\n========== Configure ${Contracts.issuance.IssuanceAllocator.name} ==========`)
    env.showMessage(`${Contracts.issuance.IssuanceAllocator.name}: ${issuanceAllocator.address}`)
    env.showMessage(`${Contracts.horizon.RewardsManager.name}: ${rewardsManager.address}`)

    // Check if already configured (shared precondition check)
    const precondition = await checkIAConfigured(
      client,
      issuanceAllocator.address,
      rewardsManager.address,
      governor,
      pauseGuardian,
    )
    if (precondition.done) {
      env.showMessage(`\n✅ ${Contracts.issuance.IssuanceAllocator.name} already configured\n`)
      return
    }

    // Get RM issuance rate (target for IA)
    const rmIssuanceRate = (await client.readContract({
      address: rewardsManager.address as `0x${string}`,
      abi: REWARDS_MANAGER_DEPRECATED_ABI,
      functionName: 'issuancePerBlock',
    })) as bigint

    if (rmIssuanceRate === 0n) {
      env.showMessage(`\n  ○ RM.issuancePerBlock is 0 — skipping IA configure\n`)
      return
    }

    // Determine what still needs configuring
    env.showMessage('\n📋 Checking current configuration...\n')

    const iaIssuanceRate = (await readFn(issuanceAllocator, { functionName: 'getIssuancePerBlock' })) as bigint
    const rateOk = iaIssuanceRate === rmIssuanceRate && iaIssuanceRate > 0n
    env.showMessage(`  Issuance rate: ${rateOk ? '✓' : '✗'} (IA: ${iaIssuanceRate}, RM: ${rmIssuanceRate})`)

    // Check role grants
    const GOVERNOR_ROLE = (await readFn(issuanceAllocator, { functionName: 'GOVERNOR_ROLE' })) as `0x${string}`
    const PAUSE_ROLE = (await readFn(issuanceAllocator, { functionName: 'PAUSE_ROLE' })) as `0x${string}`

    const governorHasRole = (await readFn(issuanceAllocator, {
      functionName: 'hasRole',
      args: [GOVERNOR_ROLE, governor],
    })) as boolean
    env.showMessage(`  Governor GOVERNOR_ROLE: ${governorHasRole ? '✓' : '✗'}`)

    const pauseGuardianHasRole = (await readFn(issuanceAllocator, {
      functionName: 'hasRole',
      args: [PAUSE_ROLE, pauseGuardian],
    })) as boolean
    env.showMessage(`  PauseGuardian PAUSE_ROLE: ${pauseGuardianHasRole ? '✓' : '✗'}`)

    // Determine executor: deployer if has GOVERNOR_ROLE, else protocol governor
    const deployerHasRole = (await readFn(issuanceAllocator, {
      functionName: 'hasRole',
      args: [GOVERNOR_ROLE, deployer],
    })) as boolean

    // Build TX data for missing configuration
    const txs: Array<{ to: string; data: `0x${string}`; label: string }> = []

    if (!rateOk) {
      txs.push({
        to: issuanceAllocator.address,
        data: encodeFunctionData({
          abi: [
            {
              inputs: [{ type: 'uint256' }],
              name: 'setIssuancePerBlock',
              outputs: [],
              stateMutability: 'nonpayable',
              type: 'function',
            },
          ],
          functionName: 'setIssuancePerBlock',
          args: [rmIssuanceRate],
        }),
        label: `setIssuancePerBlock(${rmIssuanceRate})`,
      })
    }

    if (!governorHasRole) {
      txs.push({
        to: issuanceAllocator.address,
        data: encodeFunctionData({
          abi: ACCESS_CONTROL_ENUMERABLE_ABI,
          functionName: 'grantRole',
          args: [GOVERNOR_ROLE, governor as `0x${string}`],
        }),
        label: `grantRole(GOVERNOR_ROLE, ${governor})`,
      })
    }

    if (!pauseGuardianHasRole) {
      txs.push({
        to: issuanceAllocator.address,
        data: encodeFunctionData({
          abi: ACCESS_CONTROL_ENUMERABLE_ABI,
          functionName: 'grantRole',
          args: [PAUSE_ROLE, pauseGuardian as `0x${string}`],
        }),
        label: `grantRole(PAUSE_ROLE, ${pauseGuardian})`,
      })
    }

    if (!deployerHasRole) {
      env.showMessage(`\n  ○ Deployer does not have GOVERNOR_ROLE — skipping (governance TX in upgrade step)\n`)
      return
    }

    if (txs.length === 0) return

    env.showMessage('\n🔨 Executing configuration as deployer...\n')
    const txFn = tx(env)
    for (const t of txs) {
      await txFn({ account: deployer, to: t.to as `0x${string}`, data: t.data })
      env.showMessage(`  ✓ ${t.label}`)
    }
    env.showMessage(`\n✅ ${Contracts.issuance.IssuanceAllocator.name} configuration complete!\n`)
  },
  {
    extraDependencies: [ComponentTags.REWARDS_MANAGER],
    prerequisites: [Contracts.horizon.RewardsManager],
  },
)
