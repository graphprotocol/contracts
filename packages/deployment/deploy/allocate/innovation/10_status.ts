import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { ComponentTags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { createStatusModule } from '@graphprotocol/deployment/lib/script-factories.js'
import { showDetailedComponentStatus } from '@graphprotocol/deployment/lib/status-detail.js'

/**
 * InnovationAllocation status — read-only.
 *
 * Usage:
 *   pnpm hardhat deploy --tags InnovationAllocation --network <network>
 */
export default createStatusModule(ComponentTags.INNOVATION_ALLOCATION, async (env) => {
  await showDetailedComponentStatus(env, Contracts.issuance.InnovationAllocation)
})
