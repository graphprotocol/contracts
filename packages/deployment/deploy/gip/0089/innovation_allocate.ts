import { ComponentTags, GoalTags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { applyIssuanceAllocationTable } from '@graphprotocol/deployment/lib/issuance-allocate.js'
import { createActionModule } from '@graphprotocol/deployment/lib/script-factories.js'

/**
 * GIP-0089:allocate — Apply the innovation allocation split
 *
 * Emits IA.setTargetAllocation for every target in config/<network>.json5 whose
 * on-chain allocation differs, decrease-first: RewardsManager drops to 96.584 before
 * InnovationAllocation claims 24.146, so the default target absorbs the slack within
 * the batch and never goes negative.
 *
 * That decrease-first ordering only sorts correctly once GIP-0088's issuance-connect
 * has run on the target network, so `applyIssuanceAllocationTable` verifies it and
 * refuses to build a batch otherwise (bypass: GIP_0088_ASSUME_UPGRADED=1, for
 * single-session sequenced bundle generation only).
 *
 * Never touches RM.issuancePerBlock — the config total is validated against RM's
 * on-chain rate and the run errors before emitting any TX on a mismatch.
 *
 * Idempotent: targets already at their configured allocation are skipped.
 *
 * Usage:
 *   pnpm hardhat deploy --tags GIP-0089:allocate --network <network>
 *   pnpm hardhat deploy:execute-governance --network <network>
 */
export default createActionModule(
  GoalTags.GIP_0089_ALLOCATE,
  async (env) => {
    await applyIssuanceAllocationTable(env, {
      batchName: 'gip-0089-innovation-allocation',
      goalLabel: 'GIP-0089: Innovation Allocation',
      meta: {
        name: 'GIP-0089 Innovation Allocation',
        description:
          'Reallocate 20% of issuance from RewardsManager to InnovationAllocation. Total issuance unchanged.',
      },
    })
  },
  { dependencies: [ComponentTags.INNOVATION_ALLOCATION] },
)
