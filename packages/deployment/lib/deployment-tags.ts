/**
 * Deployment Tag Library - Standardized tags for deployment scripts
 *
 * This module provides:
 * - Constants for all deployment tags
 * - Utilities to generate action-specific tags
 * - Type safety for tag usage
 *
 * Tag Patterns:
 * - Component tags: Base identifier (e.g., 'issuance-allocator')
 * - Action tags: Component + suffix (e.g., 'issuance-allocator-deploy')
 * - Category tags: Grouping tags (e.g., 'issuance-core')
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
  VERIFY: 'verify',
} as const

/**
 * Core component tags (base identifiers)
 */
export const ComponentTags = {
  // Core contracts with full lifecycle (deploy + upgrade + configure)
  ISSUANCE_ALLOCATOR: 'issuance-allocator',
  PILOT_ALLOCATION: 'pilot-allocation',
  REWARDS_RECLAIM: 'rewards-reclaim',

  // Implementations and support contracts
  DIRECT_ALLOCATION_IMPL: 'direct-allocation-impl',
  REWARDS_ELIGIBILITY: 'rewards-eligibility',

  // Process tags (not contract deployments)
  ISSUANCE_ACTIVATION: 'issuance-activation',
  VERIFY_GOVERNANCE: 'verify-governance',

  // External dependencies (Horizon contracts)
  REWARDS_MANAGER: 'rewards-manager',
  REWARDS_MANAGER_DEPLOY: 'rewards-manager-deploy',
  REWARDS_MANAGER_UPGRADE: 'rewards-manager-upgrade',

  // SubgraphService contracts
  SUBGRAPH_SERVICE: 'subgraph-service',
} as const

/**
 * Category tags for grouping deployments
 */
export const CategoryTags = {
  ISSUANCE_CORE: 'issuance-core',
  ISSUANCE_GOVERNANCE: 'issuance-governance',
  ISSUANCE: 'issuance',
} as const

/**
 * Special tags
 */
export const SpecialTags = {
  SYNC: 'sync',
} as const

/**
 * Generate action tag from component and action
 */
export function actionTag(
  component: string,
  action: (typeof DeploymentActions)[keyof typeof DeploymentActions],
): string {
  return `${component}-${action}`
}

/**
 * Common tag patterns for deployment scripts
 * Note: Arrays are not readonly to match DeployScriptModule.tags type (string[])
 */
export const Tags = {
  // IssuanceAllocator lifecycle
  issuanceAllocatorDeploy: [
    actionTag(ComponentTags.ISSUANCE_ALLOCATOR, DeploymentActions.DEPLOY),
    CategoryTags.ISSUANCE_CORE,
  ] as string[],
  issuanceAllocatorUpgrade: [actionTag(ComponentTags.ISSUANCE_ALLOCATOR, DeploymentActions.UPGRADE)] as string[],
  issuanceAllocatorConfigure: [actionTag(ComponentTags.ISSUANCE_ALLOCATOR, DeploymentActions.CONFIGURE)] as string[],
  issuanceTransfer: [actionTag(ComponentTags.ISSUANCE_ALLOCATOR, DeploymentActions.TRANSFER)] as string[],
  issuanceAllocator: [ComponentTags.ISSUANCE_ALLOCATOR] as string[], // Aggregate

  // PilotAllocation lifecycle
  pilotAllocationDeploy: [
    actionTag(ComponentTags.PILOT_ALLOCATION, DeploymentActions.DEPLOY),
    CategoryTags.ISSUANCE_CORE,
  ] as string[],
  pilotAllocationUpgrade: [actionTag(ComponentTags.PILOT_ALLOCATION, DeploymentActions.UPGRADE)] as string[],
  pilotAllocationConfigure: [actionTag(ComponentTags.PILOT_ALLOCATION, DeploymentActions.CONFIGURE)] as string[],
  pilotAllocation: [ComponentTags.PILOT_ALLOCATION] as string[], // Aggregate

  // Rewards reclaim lifecycle
  rewardsReclaimDeploy: [actionTag(ComponentTags.REWARDS_RECLAIM, DeploymentActions.DEPLOY)] as string[],
  rewardsReclaimUpgrade: [actionTag(ComponentTags.REWARDS_RECLAIM, DeploymentActions.UPGRADE)] as string[],
  rewardsReclaimConfigure: [actionTag(ComponentTags.REWARDS_RECLAIM, DeploymentActions.CONFIGURE)] as string[],
  rewardsReclaim: [ComponentTags.REWARDS_RECLAIM] as string[], // Aggregate

  // RewardsEligibilityOracle lifecycle
  rewardsEligibilityDeploy: [actionTag(ComponentTags.REWARDS_ELIGIBILITY, DeploymentActions.DEPLOY)] as string[],
  rewardsEligibilityUpgrade: [actionTag(ComponentTags.REWARDS_ELIGIBILITY, DeploymentActions.UPGRADE)] as string[],
  rewardsEligibilityConfigure: [actionTag(ComponentTags.REWARDS_ELIGIBILITY, DeploymentActions.CONFIGURE)] as string[],
  rewardsEligibilityTransfer: [actionTag(ComponentTags.REWARDS_ELIGIBILITY, DeploymentActions.TRANSFER)] as string[],
  rewardsEligibilityIntegrate: [actionTag(ComponentTags.REWARDS_ELIGIBILITY, DeploymentActions.INTEGRATE)] as string[],
  rewardsEligibility: [ComponentTags.REWARDS_ELIGIBILITY] as string[], // Aggregate

  // Support contracts
  directAllocationImpl: [ComponentTags.DIRECT_ALLOCATION_IMPL] as string[],

  // Process steps
  issuanceActivation: [ComponentTags.ISSUANCE_ACTIVATION] as string[],
  verifyGovernance: [
    ComponentTags.VERIFY_GOVERNANCE,
    CategoryTags.ISSUANCE_GOVERNANCE,
    CategoryTags.ISSUANCE,
  ] as string[],

  // Top-level aggregate
  issuanceAllocation: ['issuance-allocation'] as string[],

  // Horizon RewardsManager lifecycle
  rewardsManagerDeploy: [ComponentTags.REWARDS_MANAGER_DEPLOY] as string[],
  rewardsManagerUpgrade: [ComponentTags.REWARDS_MANAGER_UPGRADE] as string[],
  rewardsManager: [ComponentTags.REWARDS_MANAGER] as string[],

  // SubgraphService lifecycle
  subgraphServiceDeploy: [actionTag(ComponentTags.SUBGRAPH_SERVICE, DeploymentActions.DEPLOY)] as string[],
  subgraphServiceUpgrade: [actionTag(ComponentTags.SUBGRAPH_SERVICE, DeploymentActions.UPGRADE)] as string[],
  subgraphService: [ComponentTags.SUBGRAPH_SERVICE] as string[],
}
