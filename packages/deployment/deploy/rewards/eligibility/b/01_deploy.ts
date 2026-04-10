import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { requireDeployer, requireGraphToken } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { createProxyDeployModule } from '@graphprotocol/deployment/lib/script-factories.js'

export default createProxyDeployModule(
  Contracts.issuance.RewardsEligibilityOracleB,
  (env) => ({
    constructorArgs: [requireGraphToken(env).address],
    initializeArgs: [requireDeployer(env)],
  }),
  { prerequisites: [Contracts.horizon.L2GraphToken] },
)
