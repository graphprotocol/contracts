import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { ComponentTags, DeploymentActions, shouldSkipAction } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { deployProxyContract, requireDeployer } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { syncComponentsFromRegistry } from '@graphprotocol/deployment/lib/sync-utils.js'
import type { DeployScriptModule } from '@rocketh/core/types'

/**
 * Deploy DirectAllocation proxy as default reclaim address
 *
 * This script deploys a single DirectAllocation proxy instance used as the
 * default reclaim address on RewardsManager for all reclaim reasons.
 * The proxy uses the DirectAllocation_Implementation deployed by direct-allocation-impl.
 *
 * Deployed contracts:
 * - ReclaimedRewards
 *
 * Usage:
 *   pnpm hardhat deploy --tags RewardsReclaim:deploy --network <network>
 */

const func: DeployScriptModule = async (env) => {
  if (shouldSkipAction(DeploymentActions.DEPLOY)) return
  await syncComponentsFromRegistry(env, [
    Contracts.issuance.DirectAllocation_Implementation,
    Contracts.horizon.RewardsManager,
    Contracts.issuance.ReclaimedRewards,
  ])

  env.showMessage(`\n📦 Deploying DirectAllocation reclaim address proxy...`)
  env.showMessage(`   Shared implementation: ${Contracts.issuance.DirectAllocation_Implementation.name}`)

  await deployProxyContract(env, {
    contract: Contracts.issuance.ReclaimedRewards,
    sharedImplementation: Contracts.issuance.DirectAllocation_Implementation,
    initializeArgs: [requireDeployer(env)],
  })

  env.showMessage('\n✓ Reclaim address deployment complete')
}

func.tags = [ComponentTags.REWARDS_RECLAIM]
func.dependencies = [ComponentTags.DIRECT_ALLOCATION_IMPL, ComponentTags.REWARDS_MANAGER]
func.skip = async () => shouldSkipAction(DeploymentActions.DEPLOY)

export default func
