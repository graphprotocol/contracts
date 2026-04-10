import { RECURRING_COLLECTOR_PAUSE_ABI } from '@graphprotocol/deployment/lib/abis.js'
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { canSignAsGovernor, getPauseGuardian } from '@graphprotocol/deployment/lib/controller-utils.js'
import { DeploymentActions } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { requireContract } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { createActionModule } from '@graphprotocol/deployment/lib/script-factories.js'
import { graph, tx } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { PublicClient } from 'viem'
import { encodeFunctionData } from 'viem'

/**
 * Configure RecurringCollector — set pause guardian
 *
 * RC uses Controller-based access control: setPauseGuardian requires
 * msg.sender == Controller.getGovernor(). If the deployer is the
 * Controller governor (e.g. testnet), this script sets it directly.
 * Otherwise it reports the gap — the upgrade step (04_upgrade.ts)
 * bundles it as a governance TX.
 *
 * Idempotent: checks on-chain state, skips if already set.
 *
 * Usage:
 *   pnpm hardhat deploy --tags RecurringCollector:configure --network <network>
 */
export default createActionModule(Contracts.horizon.RecurringCollector, DeploymentActions.CONFIGURE, async (env) => {
  const client = graph.getPublicClient(env) as PublicClient
  const rc = requireContract(env, Contracts.horizon.RecurringCollector)
  const pauseGuardian = await getPauseGuardian(env)

  env.showMessage(`\n========== Configure ${Contracts.horizon.RecurringCollector.name} ==========`)

  const isGuardian = (await client.readContract({
    address: rc.address as `0x${string}`,
    abi: RECURRING_COLLECTOR_PAUSE_ABI,
    functionName: 'pauseGuardians',
    args: [pauseGuardian as `0x${string}`],
  })) as boolean

  if (isGuardian) {
    env.showMessage(`  ✓ Pause guardian already set\n`)
    return
  }

  const { governor, canSign } = await canSignAsGovernor(env)
  if (!canSign) {
    env.showMessage(`  ○ Pause guardian not set — will be configured in upgrade step (governance TX)\n`)
    return
  }

  env.showMessage('\n🔨 Setting pause guardian as governor...\n')
  const txFn = tx(env)
  await txFn({
    account: governor as `0x${string}`,
    to: rc.address as `0x${string}`,
    data: encodeFunctionData({
      abi: RECURRING_COLLECTOR_PAUSE_ABI,
      functionName: 'setPauseGuardian',
      args: [pauseGuardian as `0x${string}`, true],
    }),
  })
  env.showMessage(`  ✓ setPauseGuardian(${pauseGuardian})\n`)
})
