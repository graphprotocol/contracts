import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { createImplementationDeployModule } from '@graphprotocol/deployment/lib/script-factories.js'

export default createImplementationDeployModule(
  Contracts.horizon.HorizonStaking,
  (env) => {
    const controller = env.getOrNull('Controller')
    const subgraphService = env.getOrNull('SubgraphService')
    if (!controller || !subgraphService) {
      throw new Error('Missing required contract deployments (Controller, SubgraphService) after sync.')
    }
    return [controller.address, subgraphService.address]
  },
  { prerequisites: [Contracts.horizon.Controller, Contracts['subgraph-service'].SubgraphService] },
)
