import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { createImplementationDeployModule } from '@graphprotocol/deployment/lib/script-factories.js'

export default createImplementationDeployModule(
  Contracts['subgraph-service'].DisputeManager,
  (env) => {
    const controller = env.getOrNull('Controller')
    if (!controller) throw new Error('Missing Controller deployment after sync.')
    return [controller.address]
  },
  { prerequisites: [Contracts.horizon.Controller] },
)
