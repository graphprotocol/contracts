import { ACCESS_CONTROL_ENUMERABLE_ABI, REWARDS_MANAGER_ABI } from '@graphprotocol/deployment/lib/abis.js'
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { getGovernor, getPauseGuardian } from '@graphprotocol/deployment/lib/controller-utils.js'
import { ComponentTags, DeploymentActions } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { requireContract, requireDeployer } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { checkReclaimConfigured } from '@graphprotocol/deployment/lib/preconditions.js'
import { createActionModule } from '@graphprotocol/deployment/lib/script-factories.js'
import { graph, read, tx } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { PublicClient } from 'viem'
import { encodeFunctionData } from 'viem'

/**
 * Configure ReclaimedRewards — role grants only
 *
 * Grants GOVERNOR_ROLE to protocol governor and PAUSE_ROLE to pause guardian.
 * Deployer executes directly (has GOVERNOR_ROLE from deploy).
 * If deployer doesn't have the role, skips — upgrade step handles it.
 *
 * RM.setDefaultReclaimAddress is a governance TX bundled in the upgrade step.
 *
 * Usage:
 *   pnpm hardhat deploy --tags RewardsReclaim:configure --network <network>
 */
export default createActionModule(
  Contracts.issuance.ReclaimedRewards,
  DeploymentActions.CONFIGURE,
  async (env) => {
    const client = graph.getPublicClient(env) as PublicClient
    const readFn = read(env)
    const deployer = requireDeployer(env)
    const governor = await getGovernor(env)
    const pauseGuardian = await getPauseGuardian(env)

    const rewardsManager = requireContract(env, Contracts.horizon.RewardsManager)
    const reclaimedRewards = requireContract(env, Contracts.issuance.ReclaimedRewards)

    env.showMessage(`\n========== Configure ${Contracts.issuance.ReclaimedRewards.name} ==========`)
    env.showMessage(`ReclaimedRewards: ${reclaimedRewards.address}`)

    // Check if fully configured (shared precondition check)
    const precondition = await checkReclaimConfigured(
      client,
      rewardsManager.address,
      reclaimedRewards.address,
      governor,
      pauseGuardian,
    )
    if (precondition.done) {
      env.showMessage(`\n✅ ${Contracts.issuance.ReclaimedRewards.name} already configured\n`)
      return
    }

    // Check role grants
    env.showMessage('\n📋 Checking configuration...\n')

    const GOVERNOR_ROLE = (await readFn(reclaimedRewards, { functionName: 'GOVERNOR_ROLE' })) as `0x${string}`
    const PAUSE_ROLE = (await readFn(reclaimedRewards, { functionName: 'PAUSE_ROLE' })) as `0x${string}`

    const governorHasRole = (await client.readContract({
      address: reclaimedRewards.address as `0x${string}`,
      abi: ACCESS_CONTROL_ENUMERABLE_ABI,
      functionName: 'hasRole',
      args: [GOVERNOR_ROLE, governor as `0x${string}`],
    })) as boolean
    env.showMessage(`  Governor GOVERNOR_ROLE: ${governorHasRole ? '✓' : '✗'}`)

    const pauseGuardianHasRole = (await client.readContract({
      address: reclaimedRewards.address as `0x${string}`,
      abi: ACCESS_CONTROL_ENUMERABLE_ABI,
      functionName: 'hasRole',
      args: [PAUSE_ROLE, pauseGuardian as `0x${string}`],
    })) as boolean
    env.showMessage(`  PauseGuardian PAUSE_ROLE: ${pauseGuardianHasRole ? '✓' : '✗'}`)

    // RM integration status (informational — handled by upgrade step)
    try {
      const currentDefault = (await client.readContract({
        address: rewardsManager.address as `0x${string}`,
        abi: REWARDS_MANAGER_ABI,
        functionName: 'getDefaultReclaimAddress',
      })) as string
      const rmOk = currentDefault.toLowerCase() === reclaimedRewards.address.toLowerCase()
      env.showMessage(`  RM default reclaim: ${rmOk ? '✓' : '○ will be set in upgrade step (governance TX)'}`)
    } catch {
      env.showMessage(`  RM default reclaim: ○ RM not upgraded — will be set in upgrade step`)
    }

    // Execute role grants as deployer
    const deployerHasRole = (await client.readContract({
      address: reclaimedRewards.address as `0x${string}`,
      abi: ACCESS_CONTROL_ENUMERABLE_ABI,
      functionName: 'hasRole',
      args: [GOVERNOR_ROLE, deployer as `0x${string}`],
    })) as boolean

    if (!deployerHasRole) {
      env.showMessage(
        `\n  ○ Deployer does not have GOVERNOR_ROLE — skipping role grants (governance TX in upgrade step)\n`,
      )
      return
    }

    const txs: Array<{ to: string; data: `0x${string}`; label: string }> = []

    if (!governorHasRole) {
      txs.push({
        to: reclaimedRewards.address,
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
        to: reclaimedRewards.address,
        data: encodeFunctionData({
          abi: ACCESS_CONTROL_ENUMERABLE_ABI,
          functionName: 'grantRole',
          args: [PAUSE_ROLE, pauseGuardian as `0x${string}`],
        }),
        label: `grantRole(PAUSE_ROLE, ${pauseGuardian})`,
      })
    }

    if (txs.length > 0) {
      env.showMessage('\n🔨 Executing role grants as deployer...\n')
      const txFn = tx(env)
      for (const t of txs) {
        await txFn({ account: deployer, to: t.to as `0x${string}`, data: t.data })
        env.showMessage(`  ✓ ${t.label}`)
      }
    }

    env.showMessage(`\n✅ ${Contracts.issuance.ReclaimedRewards.name} role grants complete\n`)
  },
  {
    extraDependencies: [ComponentTags.REWARDS_MANAGER],
    prerequisites: [Contracts.horizon.RewardsManager],
  },
)
