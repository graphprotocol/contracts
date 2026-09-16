import {
  ComponentTags,
  DeploymentActions,
  GoalTags,
  shouldSkipAction,
} from '@graphprotocol/deployment/lib/deployment-tags.js'
import type { DeployScriptModule } from '@rocketh/core/types'

/**
 * GIP-0088:upgrade — Deploy ALL contracts and implementations
 *
 * Deploys everything required for GIP-0088 in one step:
 * - New implementations for existing proxies (RM, HS, SS, DM, PE, L2Curation)
 * - New contracts (RC, IA, DA, Reclaim, RAM, REO A/B)
 *
 * The eligibility and issuance phases start from configure, not deploy.
 *
 * Usage:
 *   pnpm hardhat deploy --tags GIP-0088:upgrade,deploy --network <network>
 */
const func: DeployScriptModule = async (env) => {
  if (shouldSkipAction(DeploymentActions.DEPLOY)) return
  env.showMessage('\n✓ GIP-0088 upgrade: all contracts and implementations deployed\n')
}

func.tags = [GoalTags.GIP_0088_UPGRADE]
func.dependencies = [
  // New implementations for existing proxies
  ComponentTags.REWARDS_MANAGER,
  ComponentTags.HORIZON_STAKING,
  ComponentTags.SUBGRAPH_SERVICE,
  ComponentTags.DISPUTE_MANAGER,
  ComponentTags.PAYMENTS_ESCROW,
  ComponentTags.L2_CURATION,
  // New contracts (proxy + implementation)
  ComponentTags.RECURRING_COLLECTOR,
  ComponentTags.ISSUANCE_ALLOCATOR,
  ComponentTags.DIRECT_ALLOCATION_IMPL,
  ComponentTags.DEFAULT_ALLOCATION,
  ComponentTags.REWARDS_RECLAIM,
  ComponentTags.RECURRING_AGREEMENT_MANAGER,
  ComponentTags.REWARDS_ELIGIBILITY_A,
  ComponentTags.REWARDS_ELIGIBILITY_B,
]
func.skip = async () => shouldSkipAction(DeploymentActions.DEPLOY)

export default func
