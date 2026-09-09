import { ComponentTags, GoalTags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { applyIssuanceAllocationTable } from '@graphprotocol/deployment/lib/issuance-allocate.js'
import { createActionModule } from '@graphprotocol/deployment/lib/script-factories.js'

/**
 * GIP-0088:issuance-allocate — Apply the configured issuance allocation table
 *
 * Sets `IA.setTargetAllocation(target, allocatorRate, selfRate)` for every target
 * named in `config/<network>.json5` (IssuanceAllocator.allocations, keyed by full
 * contract name) to exactly its configured rate — no rebalancing or residual
 * computation. The config is the complete, explicit distribution.
 *
 * Errors early (before any TX) if the config total doesn't match RM's on-chain
 * issuancePerBlock, or if the per-target rates don't sum to it
 * (see validateIssuanceAllocations). The script never sets the issuance rate.
 *
 * Idempotent: targets already at their configured allocation are skipped.
 *
 * Usage:
 *   pnpm hardhat deploy --tags GIP-0088:issuance-allocate --network <network>
 */
export default createActionModule(
  GoalTags.GIP_0088_ISSUANCE_ALLOCATE,
  async (env) => {
    await applyIssuanceAllocationTable(env, {
      batchName: 'gip-0088-issuance-allocate',
      goalLabel: 'GIP-0088: Issuance Allocate',
    })
  },
  { dependencies: [GoalTags.GIP_0088_ISSUANCE_CONNECT, ComponentTags.RECURRING_AGREEMENT_MANAGER] },
)
