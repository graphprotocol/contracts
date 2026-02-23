import { applyConfiguration, checkConfigurationStatus } from '@graphprotocol/deployment/lib/apply-configuration.js'
import { getREOConditions, getREOTransferGovernanceConditions } from '@graphprotocol/deployment/lib/contract-checks.js'
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { actionTag, ComponentTags, DeploymentActions, Tags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { requireContracts, requireDeployer } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { graph } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { DeployScriptModule } from '@rocketh/core/types'
import type { PublicClient } from 'viem'

/**
 * Transfer governance of RewardsEligibilityOracle
 *
 * See: docs/deploy/RewardsEligibilityOracleDeployment.md
 */
const func: DeployScriptModule = async (env) => {
  const deployer = requireDeployer(env)
  const [reo] = requireContracts(env, [Contracts.issuance.RewardsEligibilityOracle])
  const client = graph.getPublicClient(env) as PublicClient

  // 1. Verify preconditions (same conditions as step 4)
  env.showMessage(`\n📋 Verifying ${Contracts.issuance.RewardsEligibilityOracle.name} configuration...\n`)
  const status = await checkConfigurationStatus(client, reo.address, await getREOConditions(env))
  for (const r of status.conditions) env.showMessage(`  ${r.message}`)
  if (!status.allOk) {
    env.showMessage('\n❌ Configuration incomplete - run configure step first\n')
    process.exit(1)
  }

  // 2. Apply: revoke deployer's GOVERNOR_ROLE
  await applyConfiguration(env, client, getREOTransferGovernanceConditions(deployer), {
    contractName: `${Contracts.issuance.RewardsEligibilityOracle.name}-transfer-governance`,
    contractAddress: reo.address,
    canExecuteDirectly: true,
    executor: deployer,
  })
}

func.tags = Tags.rewardsEligibilityTransfer
func.dependencies = [actionTag(ComponentTags.REWARDS_ELIGIBILITY, DeploymentActions.CONFIGURE)]

export default func
