import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { ComponentTags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { createStatusModule } from '@graphprotocol/deployment/lib/script-factories.js'
import { showDetailedComponentStatus } from '@graphprotocol/deployment/lib/status-detail.js'

/**
 * RewardsReclaim status - show detailed state of reclaim contract
 *
 * Usage:
 *   pnpm hardhat deploy --tags RewardsReclaim --network <network>
 */
export default createStatusModule(ComponentTags.REWARDS_RECLAIM, async (env) => {
  await showDetailedComponentStatus(env, Contracts.issuance.ReclaimedRewards)
})
