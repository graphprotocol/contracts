/**
 * Deployment Tag Library
 *
 * Tags select components, skip functions gate actions:
 * - Component tags: PascalCase contract name (e.g., 'IssuanceAllocator')
 * - Action verbs: deploy, upgrade, configure, transfer, integrate, all
 * - Phase scopes: GIP-NNNN:phase (e.g., 'GIP-0088:upgrade')
 * - Activation goals: GIP-NNNN:phase-action (e.g., 'GIP-0088:eligibility-integrate')
 *
 * Usage: --tags IssuanceAllocator,deploy → matches component, deploy runs, others skip
 */

/**
 * Action suffixes for deployment scripts
 */
export const DeploymentActions = {
  DEPLOY: 'deploy',
  UPGRADE: 'upgrade',
  CONFIGURE: 'configure',
  TRANSFER: 'transfer',
  INTEGRATE: 'integrate',
  ALL: 'all',
} as const

/**
 * Core component tags (PascalCase contract names matching the registry)
 */
export const ComponentTags = {
  // Core contracts with full lifecycle (deploy + upgrade + configure)
  ISSUANCE_ALLOCATOR: 'IssuanceAllocator',
  DEFAULT_ALLOCATION: 'DefaultAllocation',
  REWARDS_RECLAIM: 'RewardsReclaim',

  // Implementations and support contracts
  DIRECT_ALLOCATION_IMPL: 'DirectAllocation_Implementation',
  REWARDS_ELIGIBILITY_A: 'RewardsEligibilityOracleA',
  REWARDS_ELIGIBILITY_B: 'RewardsEligibilityOracleB',
  REWARDS_ELIGIBILITY_MOCK: 'RewardsEligibilityOracleMock',

  // Horizon contracts
  RECURRING_COLLECTOR: 'RecurringCollector',
  REWARDS_MANAGER: 'RewardsManager',
  HORIZON_STAKING: 'HorizonStaking',
  PAYMENTS_ESCROW: 'PaymentsEscrow',

  // SubgraphService contracts
  SUBGRAPH_SERVICE: 'SubgraphService',
  DISPUTE_MANAGER: 'DisputeManager',

  // Legacy contracts (graph proxy, upgrade only)
  L2_CURATION: 'L2Curation',

  // Issuance agreement contracts
  RECURRING_AGREEMENT_MANAGER: 'RecurringAgreementManager',
} as const

/**
 * Goal tags - deployment goals that orchestrate component lifecycles
 *
 * Two-dimensional: phase scope × action verbs.
 * - Phase scopes select which contracts (`GIP-0088:upgrade`, `GIP-0088:eligibility`, etc.)
 * - Action verbs select which lifecycle step (`deploy`, `configure`, `transfer`, `upgrade`)
 * - Activation goals are phase-scoped governance TXs (`GIP-0088:eligibility-integrate`)
 * - Optional goals bypass the `all` wildcard
 *
 * Combined: `--tags GIP-0088:issuance,deploy`
 */
export const GoalTags = {
  // Overall GIP scope (status + verification)
  GIP_0088: 'GIP-0088',

  // Upgrade phase (deploy, configure, transfer, upgrade — combined with action verbs)
  GIP_0088_UPGRADE: 'GIP-0088:upgrade',

  // Activation goals (governance TXs — after upgrade complete)
  GIP_0088_ELIGIBILITY_INTEGRATE: 'GIP-0088:eligibility-integrate',
  GIP_0088_ISSUANCE_CONNECT: 'GIP-0088:issuance-connect',
  GIP_0088_ISSUANCE_ALLOCATE: 'GIP-0088:issuance-allocate',

  // Optional goals (not activated by `all`)
  GIP_0088_ELIGIBILITY_REVERT: 'GIP-0088:eligibility-revert',
  GIP_0088_ISSUANCE_CLOSE_GUARD: 'GIP-0088:issuance-close-guard',
} as const

/**
 * Special tags
 */
export const SpecialTags = {
  SYNC: 'sync',
} as const

/**
 * Parse the value of --tags from argv.
 *
 * Supports both `--tags foo,bar` (space) and `--tags=foo,bar` (equals).
 * Returns null when not present or when the space form has no following arg.
 */
function parseTagsArg(): string[] | null {
  const argv = process.argv
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]
    if (a === '--tags') {
      if (i + 1 >= argv.length) return null
      return argv[i + 1].split(',')
    }
    if (a.startsWith('--tags=')) {
      return a.slice('--tags='.length).split(',')
    }
  }
  return null
}

/**
 * Check whether --tags was specified on the command line.
 *
 * Returns true (skip) when no --tags are present. Used by status modules
 * to skip when the user didn't request any specific component.
 */
export function noTagsRequested(): boolean {
  return parseTagsArg() === null
}

/**
 * Check whether a deploy script should skip based on action verbs in --tags.
 *
 * Returns true (skip) when:
 * - No --tags specified at all (safety: require explicit tags for mutations)
 * - The verb is not present in the requested tags
 *
 * The 'all' verb is a wildcard: `--tags Component,all` activates every action
 * (deploy, upgrade, configure, transfer, integrate) plus the end verification.
 *
 * Used by script factories and custom deploy scripts to gate mutations.
 */
export function shouldSkipAction(verb: string): boolean {
  const tags = parseTagsArg()
  if (tags === null) return true
  return !tags.includes(verb) && !tags.includes(DeploymentActions.ALL)
}

/**
 * Check whether an optional goal should skip.
 *
 * Unlike `shouldSkipAction`, this does NOT respond to the `all` wildcard.
 * Optional goals only run when their specific tag is explicitly requested.
 */
export function shouldSkipOptionalGoal(goalTag: string): boolean {
  const tags = parseTagsArg()
  if (tags === null) return true
  return !tags.includes(goalTag)
}
