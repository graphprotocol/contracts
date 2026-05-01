import {
  ComponentTags,
  DeploymentActions,
  GoalTags,
  shouldSkipAction,
} from '@graphprotocol/deployment/lib/deployment-tags.js'
import type { DeployScriptModule } from '@rocketh/core/types'

/**
 * GIP-0088:upgrade — Transfer governance of all new contracts to protocol governor
 *
 * Checkpoint: component transfer scripts do the work.
 * Covers all new contracts that were deployed with deployer as governor.
 *
 * Must run AFTER configure (deployer needs GOVERNOR_ROLE to configure)
 * and BEFORE upgrade (governance must own proxies before upgrade TXs).
 *
 * Usage:
 *   pnpm hardhat deploy --tags GIP-0088:upgrade,transfer --network <network>
 */
const func: DeployScriptModule = async (env) => {
  if (shouldSkipAction(DeploymentActions.TRANSFER)) return
  env.showMessage('\n✓ GIP-0088 upgrade: governance transferred\n')
}

func.tags = [GoalTags.GIP_0088_UPGRADE]
func.dependencies = [
  ComponentTags.RECURRING_COLLECTOR,
  ComponentTags.ISSUANCE_ALLOCATOR,
  ComponentTags.DEFAULT_ALLOCATION,
  ComponentTags.RECURRING_AGREEMENT_MANAGER,
  ComponentTags.REWARDS_RECLAIM,
  ComponentTags.REWARDS_ELIGIBILITY_A,
  ComponentTags.REWARDS_ELIGIBILITY_B,
  ComponentTags.REWARDS_ELIGIBILITY_MOCK,
]
func.skip = async () => shouldSkipAction(DeploymentActions.TRANSFER)

export default func
