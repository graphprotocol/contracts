import {
  checkIssuanceAllocatorActivation,
  isRewardsManagerUpgraded,
} from '@graphprotocol/deployment/lib/contract-checks.js'
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { ComponentTags, Tags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { requireContracts } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { graph } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { DeployScriptModule } from '@rocketh/core/types'
import type { PublicClient } from 'viem'

/**
 * Full IssuanceAllocator deployment - deploy, configure, transfer governance, verify, and activate
 *
 * This is the aggregate tag for complete IssuanceAllocator setup (IssuanceAllocator.md steps 1-10):
 * 1. Deploy IssuanceAllocator proxy and implementation (deployer has initial GOVERNOR_ROLE)
 * 2-3. Configure: set rate, RM allocation (deployer executes)
 * 4-5. (Optional upgrade steps via governance)
 * 6. Transfer governance: grant roles to governance, revoke from deployer (deployer executes)
 * 7. Verify: bytecode, access control, configuration (automated verification)
 * 8-10. Generate governance TX for activation: RM integration, minter role (governance must execute)
 *
 * Requires:
 * - RewardsManager to be upgraded first (supports IIssuanceTarget)
 * - Governance to execute activation TX (steps 8-10) via Safe or deploy:execute-governance
 *
 * Usage:
 *   pnpm hardhat deploy --tags issuance-allocation --network <network>
 */
const func: DeployScriptModule = async (env) => {
  const [issuanceAllocator, rewardsManager, graphToken] = requireContracts(env, [
    Contracts.issuance.IssuanceAllocator,
    Contracts.horizon.RewardsManager,
    Contracts.horizon.L2GraphToken,
  ])

  // Verify RM has been upgraded (supports IERC165)
  const client = graph.getPublicClient(env) as PublicClient
  const upgraded = await isRewardsManagerUpgraded(client, rewardsManager.address)
  if (!upgraded) {
    env.showMessage(
      `\n❌ ${Contracts.horizon.RewardsManager.name} not upgraded - run deploy:execute-governance first\n`,
    )
    process.exit(1)
  }

  // Verify activation state
  const activation = await checkIssuanceAllocatorActivation(
    client,
    issuanceAllocator.address,
    rewardsManager.address,
    graphToken.address,
  )

  if (!activation.iaIntegrated || !activation.iaMinter) {
    env.showMessage(`\n❌ ${Contracts.issuance.IssuanceAllocator.name} not fully activated`)
    env.showMessage(
      `   IA integrated with ${Contracts.horizon.RewardsManager.name}: ${activation.iaIntegrated ? '✓' : '✗'}`,
    )
    env.showMessage(`   IA has minter role: ${activation.iaMinter ? '✓' : '✗'}\n`)
    process.exit(1)
  }

  env.showMessage(`\n✅ ${Contracts.issuance.IssuanceAllocator.name} fully deployed, configured, and activated\n`)
}

func.tags = Tags.issuanceAllocation
func.dependencies = [ComponentTags.REWARDS_MANAGER, ComponentTags.ISSUANCE_ALLOCATOR, ComponentTags.ISSUANCE_ACTIVATION]

export default func
