import { applyConfiguration } from '@graphprotocol/deployment/lib/apply-configuration.js'
import { checkREORole, getREOConditions } from '@graphprotocol/deployment/lib/contract-checks.js'
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { DeploymentActions } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { requireContracts, requireDeployer } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { createActionModule } from '@graphprotocol/deployment/lib/script-factories.js'
import { graph } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { PublicClient } from 'viem'

/**
 * Configure RewardsEligibilityOracleA (params + roles)
 *
 * Deployer executes directly (has GOVERNOR_ROLE from deploy).
 * If deployer doesn't have the role, skips — upgrade step handles it.
 */
export default createActionModule(
  Contracts.issuance.RewardsEligibilityOracleA,
  DeploymentActions.CONFIGURE,
  async (env) => {
    const [reo] = requireContracts(env, [Contracts.issuance.RewardsEligibilityOracleA])
    const client = graph.getPublicClient(env) as PublicClient
    const deployer = requireDeployer(env)

    const deployerRole = await checkREORole(client, reo.address, 'GOVERNOR_ROLE', deployer)
    if (!deployerRole.hasRole) {
      env.showMessage(
        `\n  ○ ${Contracts.issuance.RewardsEligibilityOracleA.name}: deployer does not have GOVERNOR_ROLE — skipping\n`,
      )
      return
    }

    await applyConfiguration(env, client, await getREOConditions(env), {
      contractName: Contracts.issuance.RewardsEligibilityOracleA.name,
      contractAddress: reo.address,
      canExecuteDirectly: true,
      executor: deployer,
    })
  },
)
