import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { createUpgradeModule } from '@graphprotocol/deployment/lib/script-factories.js'

export default createUpgradeModule(Contracts.issuance.RewardsEligibilityOracleA)
