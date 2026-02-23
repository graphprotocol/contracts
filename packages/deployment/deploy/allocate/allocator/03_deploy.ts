import { actionTag, ComponentTags, DeploymentActions, Tags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { requireUpgradeExecuted } from '@graphprotocol/deployment/lib/execute-governance.js'
import type { DeployScriptModule } from '@rocketh/core/types'

/**
 * IssuanceAllocator end state - deployed, upgraded, configured, and governance transferred
 *
 * Full lifecycle (steps 1-6 from IssuanceAllocator.md):
 * 1. Deploy and initialize with deployer as GOVERNOR_ROLE
 * 2-3. Configure issuance rate and RewardsManager allocation
 * 4-5. (Optional upgrade steps)
 * 6. Transfer governance to protocol governance multisig
 *
 * Usage:
 *   pnpm hardhat deploy --tags issuance-allocator --network <network>
 */
const func: DeployScriptModule = async (env) => {
  requireUpgradeExecuted(env, 'IssuanceAllocator')
  env.showMessage(`\n✓ IssuanceAllocator ready (governance transferred)`)
}

func.tags = Tags.issuanceAllocator
func.dependencies = [
  actionTag(ComponentTags.ISSUANCE_ALLOCATOR, DeploymentActions.DEPLOY),
  actionTag(ComponentTags.ISSUANCE_ALLOCATOR, DeploymentActions.UPGRADE),
  actionTag(ComponentTags.ISSUANCE_ALLOCATOR, DeploymentActions.CONFIGURE),
  actionTag(ComponentTags.ISSUANCE_ALLOCATOR, DeploymentActions.TRANSFER),
]

export default func
