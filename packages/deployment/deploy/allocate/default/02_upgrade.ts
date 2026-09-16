import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { ComponentTags, DeploymentActions, shouldSkipAction } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { syncComponentsFromRegistry } from '@graphprotocol/deployment/lib/sync-utils.js'
import { upgradeImplementation } from '@graphprotocol/deployment/lib/upgrade-implementation.js'
import type { DeployScriptModule } from '@rocketh/core/types'

// DefaultAllocation Upgrade
//
// Upgrades DefaultAllocation proxy to DirectAllocation implementation via per-proxy ProxyAdmin.

const func: DeployScriptModule = async (env) => {
  if (shouldSkipAction(DeploymentActions.UPGRADE)) return
  await syncComponentsFromRegistry(env, [
    Contracts.issuance.DirectAllocation_Implementation,
    Contracts.issuance.DefaultAllocation,
  ])
  await upgradeImplementation(env, Contracts.issuance.DefaultAllocation, {
    implementationName: 'DirectAllocation',
  })
  await syncComponentsFromRegistry(env, [Contracts.issuance.DefaultAllocation])
}

func.tags = [ComponentTags.DEFAULT_ALLOCATION]
func.dependencies = [ComponentTags.DIRECT_ALLOCATION_IMPL]
func.skip = async () => shouldSkipAction(DeploymentActions.UPGRADE)

export default func
