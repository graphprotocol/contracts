import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { createStatusModule } from '@graphprotocol/deployment/lib/script-factories.js'

export default createStatusModule(Contracts['subgraph-service'].DisputeManager)
