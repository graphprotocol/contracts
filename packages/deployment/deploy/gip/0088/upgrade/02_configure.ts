import {
  ComponentTags,
  DeploymentActions,
  GoalTags,
  shouldSkipAction,
} from '@graphprotocol/deployment/lib/deployment-tags.js'
import type { DeployScriptModule } from '@rocketh/core/types'

/**
 * GIP-0088:upgrade — Configure all contracts (deployer-only)
 *
 * Checkpoint: component 04_configure scripts do the work.
 *
 * Only items the deployer can perform run here. Items that require GOVERNOR_ROLE
 * on contracts the deployer doesn't yet control (e.g. RC.setPauseGuardian, RM
 * integration with Reclaim, deferred role grants on new contracts) are bundled
 * into the upgrade governance batch by `04_upgrade.ts`. RC's `04_configure`
 * is read-only — it just reports state.
 *
 * Usage:
 *   pnpm hardhat deploy --tags GIP-0088:upgrade,configure --network <network>
 */
const func: DeployScriptModule = async (env) => {
  if (shouldSkipAction(DeploymentActions.CONFIGURE)) return
  env.showMessage('\n✓ GIP-0088 upgrade: contracts configured\n')
}

func.tags = [GoalTags.GIP_0088_UPGRADE]
func.dependencies = [
  ComponentTags.RECURRING_COLLECTOR,
  ComponentTags.ISSUANCE_ALLOCATOR,
  ComponentTags.DEFAULT_ALLOCATION,
  ComponentTags.REWARDS_RECLAIM,
  ComponentTags.RECURRING_AGREEMENT_MANAGER,
  ComponentTags.REWARDS_ELIGIBILITY_A,
  ComponentTags.REWARDS_ELIGIBILITY_B,
]
func.skip = async () => shouldSkipAction(DeploymentActions.CONFIGURE)

export default func
