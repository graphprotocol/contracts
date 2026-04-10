import { applyConfiguration, checkConfigurationStatus } from '@graphprotocol/deployment/lib/apply-configuration.js'
import { getREOConditions, getREOTransferGovernanceConditions } from '@graphprotocol/deployment/lib/contract-checks.js'
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { DeploymentActions } from '@graphprotocol/deployment/lib/deployment-tags.js'
import {
  requireContracts,
  requireDeployer,
  transferProxyAdminOwnership,
} from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { createActionModule } from '@graphprotocol/deployment/lib/script-factories.js'
import { graph } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { PublicClient } from 'viem'

/**
 * Transfer governance of RewardsEligibilityOracleA
 */
export default createActionModule(
  Contracts.issuance.RewardsEligibilityOracleA,
  DeploymentActions.TRANSFER,
  async (env) => {
    const deployer = requireDeployer(env)
    const [reo] = requireContracts(env, [Contracts.issuance.RewardsEligibilityOracleA])
    const client = graph.getPublicClient(env) as PublicClient

    // 1. Verify preconditions (same conditions as step 4)
    env.showMessage(`\n📋 Verifying ${Contracts.issuance.RewardsEligibilityOracleA.name} configuration...\n`)
    const status = await checkConfigurationStatus(client, reo.address, await getREOConditions(env))
    for (const r of status.conditions) env.showMessage(`  ${r.message}`)
    if (!status.allOk) {
      env.showMessage('\n  ○ Configuration incomplete — skipping transfer\n')
      return
    }

    // 2. Apply: revoke deployer's GOVERNOR_ROLE
    await applyConfiguration(env, client, getREOTransferGovernanceConditions(deployer), {
      contractName: `${Contracts.issuance.RewardsEligibilityOracleA.name}-transfer-governance`,
      contractAddress: reo.address,
      canExecuteDirectly: true,
      executor: deployer,
    })

    // 3. Transfer ProxyAdmin ownership to governor
    await transferProxyAdminOwnership(env, Contracts.issuance.RewardsEligibilityOracleA)
  },
)
