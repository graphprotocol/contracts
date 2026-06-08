import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { ComponentTags, DeploymentActions, shouldSkipAction } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { deployProxyContract, requireDeployer } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { syncComponentsFromRegistry } from '@graphprotocol/deployment/lib/sync-utils.js'
import type { DeployScriptModule } from '@rocketh/core/types'

/**
 * Deploy DefaultAllocation proxy — IA's default target for unallocated issuance
 *
 * Uses the shared DirectAllocation_Implementation.
 * Initialized with deployer as governor (transferred in transfer step).
 *
 * Usage:
 *   pnpm hardhat deploy --tags DefaultAllocation,deploy --network <network>
 */
const func: DeployScriptModule = async (env) => {
  if (shouldSkipAction(DeploymentActions.DEPLOY)) return
  await syncComponentsFromRegistry(env, [
    Contracts.issuance.DirectAllocation_Implementation,
    Contracts.issuance.DefaultAllocation,
  ])

  env.showMessage(`\n📦 Deploying DefaultAllocation proxy...`)
  env.showMessage(`   Shared implementation: ${Contracts.issuance.DirectAllocation_Implementation.name}`)

  await deployProxyContract(env, {
    contract: Contracts.issuance.DefaultAllocation,
    sharedImplementation: Contracts.issuance.DirectAllocation_Implementation,
    initializeArgs: [requireDeployer(env)],
  })

  env.showMessage('\n✓ DefaultAllocation deployment complete')
}

func.tags = [ComponentTags.DEFAULT_ALLOCATION]
func.dependencies = [ComponentTags.DIRECT_ALLOCATION_IMPL]
func.skip = async () => shouldSkipAction(DeploymentActions.DEPLOY)

export default func
