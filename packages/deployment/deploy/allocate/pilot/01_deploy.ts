import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import {
  actionTag,
  ComponentTags,
  DeploymentActions,
  SpecialTags,
  Tags,
} from '@graphprotocol/deployment/lib/deployment-tags.js'
import { deployProxyContract } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import type { DeployScriptModule } from '@rocketh/core/types'

/**
 * Deploy PilotAllocation proxy using shared DirectAllocation implementation
 *
 * This deploys PilotAllocation as an OZ v5 TransparentUpgradeableProxy pointing to
 * the shared DirectAllocation_Implementation. All DirectAllocation proxies
 * share one implementation for efficiency.
 *
 * Architecture:
 * - Implementation: Shared DirectAllocation_Implementation
 * - Proxy: OZ v5 TransparentUpgradeableProxy with atomic initialization
 * - Admin: Per-proxy ProxyAdmin (created by OZ v5 proxy, owned by governor)
 *
 * Usage:
 *   pnpm hardhat deploy --tags pilot-allocation-deploy --network <network>
 */

const func: DeployScriptModule = async (env) => {
  env.showMessage(`\n📦 Deploying ${Contracts.issuance.PilotAllocation.name}...`)

  await deployProxyContract(env, {
    contract: Contracts.issuance.PilotAllocation,
    sharedImplementation: Contracts.issuance.DirectAllocation_Implementation,
    // initializeArgs defaults to [governor]
  })
}

func.tags = Tags.pilotAllocationDeploy
func.dependencies = [
  SpecialTags.SYNC,
  ComponentTags.DIRECT_ALLOCATION_IMPL,
  actionTag(ComponentTags.ISSUANCE_ALLOCATOR, DeploymentActions.DEPLOY),
]

export default func
