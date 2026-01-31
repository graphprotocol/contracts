import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { actionTag, ComponentTags, DeploymentActions, Tags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { upgradeImplementation } from '@graphprotocol/deployment/lib/upgrade-implementation.js'
import type { DeployScriptModule } from '@rocketh/core/types'

// IssuanceAllocator Upgrade
//
// Generates governance TX batch and executes upgrade via per-proxy ProxyAdmin.
//
// Workflow:
// 1. Check for pending implementation in address book
// 2. Generate governance TX (upgradeAndCall to per-proxy ProxyAdmin)
// 3. Fork mode: execute via governor impersonation
// 4. Production: output TX file for Safe execution
//
// Usage:
//   FORK_NETWORK=arbitrumSepolia npx hardhat deploy --tags issuance-allocator-upgrade --network localhost

const func: DeployScriptModule = async (env) => {
  await upgradeImplementation(env, Contracts.issuance.IssuanceAllocator)
}

func.tags = Tags.issuanceAllocatorUpgrade
func.dependencies = [actionTag(ComponentTags.ISSUANCE_ALLOCATOR, DeploymentActions.DEPLOY)]

export default func
