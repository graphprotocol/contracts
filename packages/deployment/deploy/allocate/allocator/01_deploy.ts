import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { SpecialTags, Tags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { deployProxyContract, requireContract } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import type { DeployScriptModule } from '@rocketh/core/types'

/**
 * Deploy IssuanceAllocator - Token allocation contract with transparent proxy
 *
 * This deploys IssuanceAllocator as an upgradeable contract using OpenZeppelin v5's
 * TransparentUpgradeableProxy pattern. The contract is initialized atomically
 * during proxy deployment to prevent front-running attacks.
 *
 * Architecture:
 * - Implementation: IssuanceAllocator contract with GRT token constructor arg
 * - Proxy: OZ v5 TransparentUpgradeableProxy with atomic initialization
 * - Admin: Per-proxy ProxyAdmin (created by OZ v5 proxy, owned by governor)
 *
 * Initial Setup (IssuanceAllocator.md Step 1):
 * - Governor receives initial GOVERNOR_ROLE for configuration
 * - Per-proxy ProxyAdmin owned by governor (controls upgrades)
 * - Default target set to address(0) (no minting until configured)
 * - Governance transfer happens in separate script
 *
 * Deployment strategy:
 * - First run: Deploy implementation + proxy (creates per-proxy ProxyAdmin)
 * - Subsequent runs:
 *   - If implementation unchanged: No-op (reuse existing)
 *   - If implementation changed: Deploy new implementation, store as pending
 *   - Upgrades must be done via governance
 *
 * Usage:
 *   pnpm hardhat deploy --tags issuance-allocator-deploy --network <network>
 */

const func: DeployScriptModule = async (env) => {
  const graphToken = requireContract(env, Contracts.horizon.L2GraphToken).address

  env.showMessage(`\n📦 Deploying ${Contracts.issuance.IssuanceAllocator.name} with GraphToken: ${graphToken}`)

  await deployProxyContract(env, {
    contract: Contracts.issuance.IssuanceAllocator,
    constructorArgs: [graphToken],
  })
}

func.tags = Tags.issuanceAllocatorDeploy
func.dependencies = [SpecialTags.SYNC]

export default func
