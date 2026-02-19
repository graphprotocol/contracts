import { actionTag, ComponentTags, DeploymentActions, Tags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { requireUpgradeExecuted } from '@graphprotocol/deployment/lib/execute-governance.js'
import type { DeployScriptModule } from '@rocketh/core/types'

/**
 * PilotAllocation end state - deployed, upgraded, and configured
 *
 * Aggregate tag that ensures PilotAllocation is fully ready:
 * - Proxy and implementation deployed
 * - Proxy upgraded to latest implementation
 * - Configured as IssuanceAllocator target
 *
 * Usage:
 *   pnpm hardhat deploy --tags pilot-allocation --network <network>
 */
const func: DeployScriptModule = async (env) => {
  requireUpgradeExecuted(env, 'PilotAllocation')
  env.showMessage(`\n✓ PilotAllocation ready`)
}

func.tags = Tags.pilotAllocation
func.dependencies = [
  actionTag(ComponentTags.PILOT_ALLOCATION, DeploymentActions.DEPLOY),
  actionTag(ComponentTags.PILOT_ALLOCATION, DeploymentActions.UPGRADE),
  actionTag(ComponentTags.PILOT_ALLOCATION, DeploymentActions.CONFIGURE),
]

export default func
