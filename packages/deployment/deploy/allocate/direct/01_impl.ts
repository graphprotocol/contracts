import { loadDirectAllocationArtifact } from '@graphprotocol/deployment/lib/artifact-loaders.js'
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { computeArtifactBytecodeHash } from '@graphprotocol/deployment/lib/deploy-implementation.js'
import { buildDeploymentMetadata } from '@graphprotocol/deployment/lib/deployment-metadata.js'
import { ComponentTags, DeploymentActions, shouldSkipAction } from '@graphprotocol/deployment/lib/deployment-tags.js'
import {
  requireDeployer,
  requireGraphToken,
  showDeploymentStatus,
} from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { syncComponentsFromRegistry } from '@graphprotocol/deployment/lib/sync-utils.js'
import { deploy, graph } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { DeployScriptModule } from '@rocketh/core/types'

/**
 * Deploy shared DirectAllocation implementation
 *
 * This implementation is shared by all DirectAllocation proxies
 * (DefaultAllocation, ReclaimedRewards). Runs during both deploy AND upgrade
 * actions — deploying the implementation is a prerequisite for proxy upgrades.
 *
 * Rocketh handles idempotency: if bytecode is unchanged, no redeployment occurs.
 *
 * Usage:
 *   pnpm hardhat deploy --tags DirectAllocation_Implementation,deploy --network <network>
 */
const func: DeployScriptModule = async (env) => {
  // Run for both deploy and upgrade actions
  if (shouldSkipAction(DeploymentActions.DEPLOY) && shouldSkipAction(DeploymentActions.UPGRADE)) return

  await syncComponentsFromRegistry(env, [
    Contracts.issuance.DirectAllocation_Implementation,
    Contracts.horizon.L2GraphToken,
  ])

  const deployFn = deploy(env)
  const deployer = requireDeployer(env)
  const graphTokenDep = requireGraphToken(env)

  env.showMessage(`\n📦 Deploying shared ${Contracts.issuance.DirectAllocation_Implementation.name}...`)

  const artifact = loadDirectAllocationArtifact()
  const result = await deployFn(Contracts.issuance.DirectAllocation_Implementation.name, {
    account: deployer,
    artifact,
    args: [graphTokenDep.address],
  })

  // Persist to address book — only write metadata on new deployments
  // to avoid overwriting stored hash with current artifact when deploy was a no-op
  if (result.newlyDeployed) {
    const metadata = buildDeploymentMetadata(
      result,
      computeArtifactBytecodeHash(Contracts.issuance.DirectAllocation_Implementation.artifact!),
    )
    if (metadata) {
      await graph.updateIssuanceAddressBook(env, {
        name: Contracts.issuance.DirectAllocation_Implementation.name,
        address: result.address,
        deployment: metadata,
      })
    }
  }

  showDeploymentStatus(env, Contracts.issuance.DirectAllocation_Implementation, result)

  await syncComponentsFromRegistry(env, [Contracts.issuance.DirectAllocation_Implementation])
}

func.tags = [ComponentTags.DIRECT_ALLOCATION_IMPL]
func.dependencies = []
func.skip = async () => shouldSkipAction(DeploymentActions.DEPLOY) && shouldSkipAction(DeploymentActions.UPGRADE)

export default func
