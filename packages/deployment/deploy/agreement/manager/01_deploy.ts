import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { requireDeployer, requireGraphToken } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { createProxyDeployModule } from '@graphprotocol/deployment/lib/script-factories.js'

export default createProxyDeployModule(
  Contracts.issuance.RecurringAgreementManager,
  (env) => {
    const paymentsEscrow = env.getOrNull('PaymentsEscrow')
    if (!paymentsEscrow) throw new Error('Missing PaymentsEscrow deployment after sync.')
    return {
      constructorArgs: [requireGraphToken(env).address, paymentsEscrow.address],
      initializeArgs: [requireDeployer(env)],
    }
  },
  { prerequisites: [Contracts.horizon.L2GraphToken, Contracts.horizon.PaymentsEscrow] },
)
