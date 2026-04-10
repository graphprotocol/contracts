import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { requireContract, requireDeployer } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { createProxyDeployModule } from '@graphprotocol/deployment/lib/script-factories.js'

export default createProxyDeployModule(
  Contracts.issuance.IssuanceAllocator,
  (env) => ({
    constructorArgs: [requireContract(env, Contracts.horizon.L2GraphToken).address],
    initializeArgs: [requireDeployer(env)],
  }),
  { prerequisites: [Contracts.horizon.L2GraphToken] },
)
