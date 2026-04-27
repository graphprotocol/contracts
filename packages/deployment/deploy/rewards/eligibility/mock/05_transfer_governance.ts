import { applyConfiguration } from '@graphprotocol/deployment/lib/apply-configuration.js'
import { getREOTransferGovernanceConditions } from '@graphprotocol/deployment/lib/contract-checks.js'
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
 * Transfer governance of MockRewardsEligibilityOracle
 *
 * Revokes deployer's GOVERNOR_ROLE and transfers ProxyAdmin ownership
 * to the protocol governor.
 */
export default createActionModule(
  Contracts.issuance.RewardsEligibilityOracleMock,
  DeploymentActions.TRANSFER,
  async (env) => {
    const deployer = requireDeployer(env)
    const [reo] = requireContracts(env, [Contracts.issuance.RewardsEligibilityOracleMock])
    const client = graph.getPublicClient(env) as PublicClient

    // Revoke deployer's GOVERNOR_ROLE
    await applyConfiguration(env, client, getREOTransferGovernanceConditions(deployer), {
      contractName: `${Contracts.issuance.RewardsEligibilityOracleMock.name}-transfer-governance`,
      contractAddress: reo.address,
      canExecuteDirectly: true,
      executor: deployer,
    })

    // Transfer ProxyAdmin ownership to governor
    await transferProxyAdminOwnership(env, Contracts.issuance.RewardsEligibilityOracleMock)
  },
)
