import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { createImplementationDeployModule } from '@graphprotocol/deployment/lib/script-factories.js'

export default createImplementationDeployModule(Contracts.horizon.RewardsManager)
