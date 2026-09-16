import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { ComponentTags, DeploymentActions, shouldSkipAction } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { deployProxyContract, requireDeployer } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { syncComponentsFromRegistry } from '@graphprotocol/deployment/lib/sync-utils.js'
import type { DeployScriptModule } from '@rocketh/core/types'

/**
 * Deploy InnovationAllocation proxy — GIP-0089 innovation allocation target
 *
 * Uses the shared DirectAllocation_Implementation. Initialized with the deployer as
 * governor so 04_configure can grant roles directly; 05_transfer_governance then
 * revokes the deployer and hands the ProxyAdmin to the protocol governor.
 *
 * Idempotent: rocketh skips when the proxy already exists.
 *
 * Usage:
 *   pnpm hardhat deploy --tags InnovationAllocation,deploy --network <network>
 */
const func: DeployScriptModule = async (env) => {
  if (shouldSkipAction(DeploymentActions.DEPLOY)) return
  await syncComponentsFromRegistry(env, [
    Contracts.issuance.DirectAllocation_Implementation,
    Contracts.issuance.InnovationAllocation,
  ])

  env.showMessage(`\n📦 Deploying InnovationAllocation proxy...`)
  env.showMessage(`   Shared implementation: ${Contracts.issuance.DirectAllocation_Implementation.name}`)

  await deployProxyContract(env, {
    contract: Contracts.issuance.InnovationAllocation,
    sharedImplementation: Contracts.issuance.DirectAllocation_Implementation,
    initializeArgs: [requireDeployer(env)],
  })

  env.showMessage('\n✓ InnovationAllocation deployment complete')
}

func.tags = [ComponentTags.INNOVATION_ALLOCATION]
func.dependencies = [ComponentTags.DIRECT_ALLOCATION_IMPL]
func.skip = async () => shouldSkipAction(DeploymentActions.DEPLOY)

export default func
