import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { ComponentTags, DeploymentActions, shouldSkipAction } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { syncComponentsFromRegistry } from '@graphprotocol/deployment/lib/sync-utils.js'
import { upgradeImplementation } from '@graphprotocol/deployment/lib/upgrade-implementation.js'
import type { DeployScriptModule } from '@rocketh/core/types'

/**
 * InnovationAllocation upgrade
 *
 * Upgrades the InnovationAllocation proxy to the shared DirectAllocation
 * implementation via its per-proxy ProxyAdmin. Emits a governance TX batch when the
 * deployer cannot sign as governor; executes directly in fork mode.
 *
 * Usage:
 *   pnpm hardhat deploy --tags InnovationAllocation,upgrade --network <network>
 */
const func: DeployScriptModule = async (env) => {
  if (shouldSkipAction(DeploymentActions.UPGRADE)) return
  await syncComponentsFromRegistry(env, [
    Contracts.issuance.DirectAllocation_Implementation,
    Contracts.issuance.InnovationAllocation,
  ])
  await upgradeImplementation(env, Contracts.issuance.InnovationAllocation, {
    implementationName: 'DirectAllocation',
  })
  await syncComponentsFromRegistry(env, [Contracts.issuance.InnovationAllocation])
}

func.tags = [ComponentTags.INNOVATION_ALLOCATION]
func.dependencies = [ComponentTags.DIRECT_ALLOCATION_IMPL]
func.skip = async () => shouldSkipAction(DeploymentActions.UPGRADE)

export default func
