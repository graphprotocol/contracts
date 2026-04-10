import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { createEndModule } from '@graphprotocol/deployment/lib/script-factories.js'

export default createEndModule(Contracts.issuance.ReclaimedRewards)
