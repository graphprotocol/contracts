import { ACCESS_CONTROL_ENUMERABLE_ABI } from '@graphprotocol/deployment/lib/abis.js'
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { getGovernor, getPauseGuardian } from '@graphprotocol/deployment/lib/controller-utils.js'
import { DeploymentActions } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { requireContract, requireDeployer } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { checkDefaultAllocationConfigured } from '@graphprotocol/deployment/lib/preconditions.js'
import { createActionModule } from '@graphprotocol/deployment/lib/script-factories.js'
import { graph, read, tx } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { PublicClient } from 'viem'
import { encodeFunctionData } from 'viem'

/**
 * Configure DefaultAllocation
 *
 * - Grants GOVERNOR_ROLE to protocol governor
 * - Grants PAUSE_ROLE to pause guardian
 *
 * Note: IA.setDefaultTarget(DA) is an activation step in issuance-connect,
 * not a configure step (requires IA to have minter role).
 *
 * Idempotent: checks on-chain state, skips if already configured.
 *
 * Usage:
 *   pnpm hardhat deploy --tags DefaultAllocation,configure --network <network>
 */
export default createActionModule(Contracts.issuance.DefaultAllocation, DeploymentActions.CONFIGURE, async (env) => {
  const client = graph.getPublicClient(env) as PublicClient
  const readFn = read(env)
  const deployer = requireDeployer(env)
  const governor = await getGovernor(env)
  const pauseGuardian = await getPauseGuardian(env)

  const defaultAllocation = requireContract(env, Contracts.issuance.DefaultAllocation)

  env.showMessage(`\n========== Configure ${Contracts.issuance.DefaultAllocation.name} ==========`)
  env.showMessage(`DefaultAllocation: ${defaultAllocation.address}`)

  // Check if already configured (shared precondition check)
  const precondition = await checkDefaultAllocationConfigured(
    client,
    defaultAllocation.address,
    governor,
    pauseGuardian,
  )
  if (precondition.done) {
    env.showMessage(`\n✅ ${Contracts.issuance.DefaultAllocation.name} already configured\n`)
    return
  }

  env.showMessage('\n📋 Checking current configuration...\n')

  const GOVERNOR_ROLE = (await readFn(defaultAllocation, { functionName: 'GOVERNOR_ROLE' })) as `0x${string}`
  const PAUSE_ROLE = (await readFn(defaultAllocation, { functionName: 'PAUSE_ROLE' })) as `0x${string}`

  const governorHasRole = (await client.readContract({
    address: defaultAllocation.address as `0x${string}`,
    abi: ACCESS_CONTROL_ENUMERABLE_ABI,
    functionName: 'hasRole',
    args: [GOVERNOR_ROLE, governor as `0x${string}`],
  })) as boolean
  env.showMessage(`  Governor GOVERNOR_ROLE: ${governorHasRole ? '✓' : '✗'}`)

  const pauseGuardianHasRole = (await client.readContract({
    address: defaultAllocation.address as `0x${string}`,
    abi: ACCESS_CONTROL_ENUMERABLE_ABI,
    functionName: 'hasRole',
    args: [PAUSE_ROLE, pauseGuardian as `0x${string}`],
  })) as boolean
  env.showMessage(`  PauseGuardian PAUSE_ROLE: ${pauseGuardianHasRole ? '✓' : '✗'}`)

  const deployerHasRole = (await client.readContract({
    address: defaultAllocation.address as `0x${string}`,
    abi: ACCESS_CONTROL_ENUMERABLE_ABI,
    functionName: 'hasRole',
    args: [GOVERNOR_ROLE, deployer as `0x${string}`],
  })) as boolean

  const txs: Array<{ to: string; data: `0x${string}`; label: string }> = []

  if (!governorHasRole) {
    txs.push({
      to: defaultAllocation.address,
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
      to: defaultAllocation.address,
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

  env.showMessage('\n🔨 Executing role grants as deployer...\n')
  const txFn = tx(env)
  for (const t of txs) {
    await txFn({ account: deployer, to: t.to as `0x${string}`, data: t.data })
    env.showMessage(`  ✓ ${t.label}`)
  }

  env.showMessage(`\n✅ ${Contracts.issuance.DefaultAllocation.name} configuration complete!\n`)
})
