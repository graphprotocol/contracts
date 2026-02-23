import { getTargetChainIdFromEnv } from '@graphprotocol/deployment/lib/address-book-utils.js'
import { loadDirectAllocationArtifact } from '@graphprotocol/deployment/lib/artifact-loaders.js'
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { SpecialTags, Tags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import {
  requireDeployer,
  requireGraphToken,
  showDeploymentStatus,
} from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { deploy, graph } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { DeployScriptModule } from '@rocketh/core/types'

/**
 * Deploy shared DirectAllocation implementation
 *
 * This implementation is shared by all DirectAllocation proxies:
 * - PilotAllocation
 * - ReclaimAddress_Treasury
 * - (other ReclaimAddress_* instances)
 *
 * Deploying once and sharing reduces gas costs and ensures all instances
 * are on the same version.
 *
 * Usage:
 *   pnpm hardhat deploy --tags direct-allocation-impl --network <network>
 */

const func: DeployScriptModule = async (env) => {
  const deployFn = deploy(env)

  const deployer = requireDeployer(env)

  // Require L2GraphToken from deployments JSON (Graph Token on L2)
  const graphTokenDep = requireGraphToken(env)

  env.showMessage(`\n📦 Deploying shared ${Contracts.issuance.DirectAllocation_Implementation.name}...`)

  const artifact = loadDirectAllocationArtifact()
  const result = await deployFn(
    Contracts.issuance.DirectAllocation_Implementation.name,
    {
      account: deployer,
      artifact,
      args: [graphTokenDep.address],
    },
    {
      skipIfAlreadyDeployed: true,
    },
  )

  showDeploymentStatus(env, Contracts.issuance.DirectAllocation_Implementation, result)

  // Set pendingImplementation for all proxies that use DirectAllocation
  // This allows the upgrade scripts to read from address book instead of deployment records
  const targetChainId = await getTargetChainIdFromEnv(env)
  const addressBook = graph.getIssuanceAddressBook(targetChainId)

  const proxiesToUpdate = [Contracts.issuance.PilotAllocation.name]
  for (const proxyName of proxiesToUpdate) {
    try {
      const entry = addressBook.getEntry(proxyName as Parameters<typeof addressBook.getEntry>[0])
      if (entry) {
        addressBook.setPendingImplementation(
          proxyName as Parameters<typeof addressBook.setPendingImplementation>[0],
          result.address,
          {
            txHash: result.transaction?.hash,
          },
        )
        env.showMessage(`   ✓ Set pendingImplementation for ${proxyName}`)
      }
    } catch {
      // Entry doesn't exist yet - will be created by deploy script
      env.showMessage(`   - ${proxyName} not in address book yet, skipping`)
    }
  }
}

func.tags = Tags.directAllocationImpl
func.dependencies = [SpecialTags.SYNC]

export default func
