import { actionTag, ComponentTags, DeploymentActions, Tags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { requireUpgradeExecuted } from '@graphprotocol/deployment/lib/execute-governance.js'
import type { DeployScriptModule } from '@rocketh/core/types'

/**
 * SubgraphService end state - deployed and upgraded
 *
 * Usage:
 *   pnpm hardhat deploy --tags subgraph-service --network <network>
 */
const func: DeployScriptModule = async (env) => {
  requireUpgradeExecuted(env, 'SubgraphService')
  env.showMessage(`\n✓ SubgraphService ready`)
}

func.tags = Tags.subgraphService
func.dependencies = [
  actionTag(ComponentTags.SUBGRAPH_SERVICE, DeploymentActions.DEPLOY),
  actionTag(ComponentTags.SUBGRAPH_SERVICE, DeploymentActions.UPGRADE),
]

export default func
