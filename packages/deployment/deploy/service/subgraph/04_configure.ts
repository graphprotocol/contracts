import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { DeploymentActions } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { createActionModule } from '@graphprotocol/deployment/lib/script-factories.js'

/**
 * Configure SubgraphService
 *
 * In the current contract version, RecurringCollector is set as an immutable
 * constructor argument — no runtime authorization is needed.
 *
 * This script is a no-op placeholder for future configuration needs.
 *
 * Usage:
 *   pnpm hardhat deploy --tags SubgraphService:configure --network <network>
 */
export default createActionModule(
  Contracts['subgraph-service'].SubgraphService,
  DeploymentActions.CONFIGURE,
  async (env) => {
    env.showMessage(`\n✅ SubgraphService: RecurringCollector is set at construction time, no configuration needed\n`)
  },
)
