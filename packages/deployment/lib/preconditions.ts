/**
 * Shared Precondition Checks
 *
 * Each function answers "is this action step done?" for a specific component.
 * Used by BOTH action scripts (to skip if done) and status scripts (for next-step hints).
 *
 * This is the SINGLE SOURCE OF TRUTH for precondition logic.
 * Action scripts and status scripts must call the same functions — no copies.
 *
 * Configure checks: params, integration references, and role GRANTS (PAUSE_ROLE, GOVERNOR_ROLE)
 * Transfer checks: deployer GOVERNOR_ROLE REVOKE + ProxyAdmin ownership
 */

import type { PublicClient } from 'viem'
import { keccak256, toHex } from 'viem'

import {
  ACCESS_CONTROL_ENUMERABLE_ABI,
  ISSUANCE_ALLOCATOR_ABI,
  ISSUANCE_TARGET_ABI,
  OZ_PROXY_ADMIN_ABI,
  REWARDS_MANAGER_ABI,
  REWARDS_MANAGER_DEPRECATED_ABI,
} from './abis.js'

// ============================================================================
// Result type
// ============================================================================

/**
 * Result of a precondition check
 *
 * @property done - true if the action step is complete (on-chain state matches target)
 * @property reason - why not done (human-readable, for status display)
 */
export interface PreconditionResult {
  done: boolean
  reason?: string
}

// ============================================================================
// Helpers
// ============================================================================

// Precomputed role hashes (matches BaseUpgradeable constants)
const GOVERNOR_ROLE = keccak256(toHex('GOVERNOR_ROLE'))
const PAUSE_ROLE = keccak256(toHex('PAUSE_ROLE'))

/** Check if account has a role on a contract */
async function hasRole(
  client: PublicClient,
  contractAddress: string,
  role: `0x${string}`,
  account: string,
): Promise<boolean> {
  return (await client.readContract({
    address: contractAddress as `0x${string}`,
    abi: ACCESS_CONTROL_ENUMERABLE_ABI,
    functionName: 'hasRole',
    args: [role, account as `0x${string}`],
  })) as boolean
}

/**
 * Check role grants common to all deployer-initialized contracts
 *
 * Configure must grant:
 * - GOVERNOR_ROLE to protocol governor
 * - PAUSE_ROLE to pause guardian
 */
async function checkRoleGrants(
  client: PublicClient,
  contractAddress: string,
  governor: string,
  pauseGuardian: string,
): Promise<{ governorOk: boolean; pauseOk: boolean; reasons: string[] }> {
  const governorOk = await hasRole(client, contractAddress, GOVERNOR_ROLE, governor)
  const pauseOk = await hasRole(client, contractAddress, PAUSE_ROLE, pauseGuardian)

  const reasons: string[] = []
  if (!governorOk) reasons.push('governor missing GOVERNOR_ROLE')
  if (!pauseOk) reasons.push('pauseGuardian missing PAUSE_ROLE')

  return { governorOk, pauseOk, reasons }
}

// ============================================================================
// Configure checks
// ============================================================================

/**
 * Check if IssuanceAllocator is configured
 *
 * Matches the skip logic in allocate/allocator/04_configure.ts:
 * - RM.issuancePerBlock must be > 0 (RM initialized)
 * - IA.getIssuancePerBlock() must equal RM rate
 * - governor has GOVERNOR_ROLE
 * - pauseGuardian has PAUSE_ROLE
 *
 * Note: RM target allocation (setTargetAllocation) is an activation step
 * in issuance-connect, not a configure step.
 */
export async function checkIAConfigured(
  client: PublicClient,
  iaAddress: string,
  rmAddress: string,
  governor: string,
  pauseGuardian: string,
): Promise<PreconditionResult> {
  // Check RM issuance rate
  const rmIssuanceRate = (await client.readContract({
    address: rmAddress as `0x${string}`,
    abi: REWARDS_MANAGER_DEPRECATED_ABI,
    functionName: 'issuancePerBlock',
  })) as bigint

  if (rmIssuanceRate === 0n) {
    return { done: false, reason: 'RM.issuancePerBlock is 0' }
  }

  // Check IA rate matches RM
  const iaIssuanceRate = (await client.readContract({
    address: iaAddress as `0x${string}`,
    abi: ISSUANCE_ALLOCATOR_ABI,
    functionName: 'getIssuancePerBlock',
  })) as bigint

  const rateOk = iaIssuanceRate === rmIssuanceRate && iaIssuanceRate > 0n

  // Check role grants
  const roles = await checkRoleGrants(client, iaAddress, governor, pauseGuardian)

  if (rateOk && roles.governorOk && roles.pauseOk) {
    return { done: true }
  }

  const reasons: string[] = []
  if (!rateOk) reasons.push('rate mismatch')
  reasons.push(...roles.reasons)
  return { done: false, reason: reasons.join(', ') }
}

/**
 * Check if RecurringAgreementManager is configured
 *
 * Matches the skip logic in agreement/manager/04_configure.ts:
 * - RC has COLLECTOR_ROLE
 * - SS has DATA_SERVICE_ROLE
 * - RAM.getIssuanceAllocator() == IA
 * - governor has GOVERNOR_ROLE
 * - pauseGuardian has PAUSE_ROLE
 */
export async function checkRAMConfigured(
  client: PublicClient,
  ramAddress: string,
  rcAddress: string,
  ssAddress: string,
  iaAddress: string,
  governor: string,
  pauseGuardian: string,
): Promise<PreconditionResult> {
  const COLLECTOR_ROLE = keccak256(toHex('COLLECTOR_ROLE'))
  const DATA_SERVICE_ROLE = keccak256(toHex('DATA_SERVICE_ROLE'))

  const rcHasCollectorRole = (await client.readContract({
    address: ramAddress as `0x${string}`,
    abi: ACCESS_CONTROL_ENUMERABLE_ABI,
    functionName: 'hasRole',
    args: [COLLECTOR_ROLE, rcAddress as `0x${string}`],
  })) as boolean

  const ssHasDataServiceRole = (await client.readContract({
    address: ramAddress as `0x${string}`,
    abi: ACCESS_CONTROL_ENUMERABLE_ABI,
    functionName: 'hasRole',
    args: [DATA_SERVICE_ROLE, ssAddress as `0x${string}`],
  })) as boolean

  let iaConfigured = false
  try {
    const currentIA = (await client.readContract({
      address: ramAddress as `0x${string}`,
      abi: ISSUANCE_TARGET_ABI,
      functionName: 'getIssuanceAllocator',
    })) as string
    iaConfigured = currentIA.toLowerCase() === iaAddress.toLowerCase()
  } catch {
    // Not set
  }

  // Check role grants
  const roles = await checkRoleGrants(client, ramAddress, governor, pauseGuardian)

  if (rcHasCollectorRole && ssHasDataServiceRole && iaConfigured && roles.governorOk && roles.pauseOk) {
    return { done: true }
  }

  const reasons: string[] = []
  if (!rcHasCollectorRole) reasons.push('RC missing COLLECTOR_ROLE')
  if (!ssHasDataServiceRole) reasons.push('SS missing DATA_SERVICE_ROLE')
  if (!iaConfigured) reasons.push('IssuanceAllocator not set')
  reasons.push(...roles.reasons)
  return { done: false, reason: reasons.join(', ') }
}

/**
 * Check Reclaim role grants only (governor has GOVERNOR_ROLE, pauseGuardian has PAUSE_ROLE)
 *
 * Use this when you need to know whether the deployer (with Reclaim GOVERNOR_ROLE) can
 * fix the issue. The RM integration is governance-only and should be checked separately
 * via checkReclaimRMIntegration.
 */
export async function checkReclaimRoles(
  client: PublicClient,
  reclaimAddress: string,
  governor: string,
  pauseGuardian: string,
): Promise<PreconditionResult> {
  const roles = await checkRoleGrants(client, reclaimAddress, governor, pauseGuardian)
  if (roles.governorOk && roles.pauseOk) {
    return { done: true }
  }
  return { done: false, reason: roles.reasons.join(', ') }
}

/**
 * Check RM integration with Reclaim: RM.getDefaultReclaimAddress() == reclaim address
 *
 * This is governance-only — only an account with GOVERNOR_ROLE on RM can fix it,
 * which the deployer never has. Status logic should always treat a failure here
 * as deferred (governance TX), not blocking on configure.
 */
export async function checkReclaimRMIntegration(
  client: PublicClient,
  rmAddress: string,
  reclaimAddress: string,
): Promise<PreconditionResult> {
  try {
    const currentDefault = (await client.readContract({
      address: rmAddress as `0x${string}`,
      abi: REWARDS_MANAGER_ABI,
      functionName: 'getDefaultReclaimAddress',
    })) as string

    if (currentDefault.toLowerCase() === reclaimAddress.toLowerCase()) {
      return { done: true }
    }
    return { done: false, reason: 'default reclaim address not set' }
  } catch {
    // Function not available — RM not upgraded
    return { done: false, reason: 'RM not upgraded' }
  }
}

/**
 * Check if ReclaimedRewards is fully configured (roles + RM integration)
 *
 * Convenience wrapper that combines checkReclaimRoles and checkReclaimRMIntegration.
 * Use the split functions when callers need to distinguish deployer-fixable role
 * issues from governance-only RM integration issues.
 */
export async function checkReclaimConfigured(
  client: PublicClient,
  rmAddress: string,
  reclaimAddress: string,
  governor: string,
  pauseGuardian: string,
): Promise<PreconditionResult> {
  const roles = await checkReclaimRoles(client, reclaimAddress, governor, pauseGuardian)
  const rmIntegration = await checkReclaimRMIntegration(client, rmAddress, reclaimAddress)

  if (roles.done && rmIntegration.done) {
    return { done: true }
  }

  // If roles are done but RM not upgraded, report that specifically
  if (roles.done && rmIntegration.reason === 'RM not upgraded') {
    return { done: false, reason: 'RM not upgraded' }
  }

  const reasons: string[] = []
  if (!roles.done && roles.reason) reasons.push(roles.reason)
  if (!rmIntegration.done && rmIntegration.reason) reasons.push(rmIntegration.reason)
  return { done: false, reason: reasons.join(', ') }
}

/**
 * Check if DefaultAllocation is configured
 *
 * - governor has GOVERNOR_ROLE on DefaultAllocation
 * - pauseGuardian has PAUSE_ROLE on DefaultAllocation
 *
 * Note: IA.setDefaultTarget(DA) is an activation step in issuance-connect.
 */
export async function checkDefaultAllocationConfigured(
  client: PublicClient,
  daAddress: string,
  governor: string,
  pauseGuardian: string,
): Promise<PreconditionResult> {
  const roles = await checkRoleGrants(client, daAddress, governor, pauseGuardian)

  if (roles.governorOk && roles.pauseOk) {
    return { done: true }
  }

  return { done: false, reason: roles.reasons.join(', ') }
}

// ============================================================================
// Transfer checks
// ============================================================================

/**
 * Check if deployer GOVERNOR_ROLE is revoked on a contract
 *
 * Transfer = revoke deployer access. Role grants happen in configure.
 * Generic check used for IA, RAM, Reclaim.
 */
export async function checkDeployerRevoked(
  client: PublicClient,
  contractAddress: string,
  deployer: string,
): Promise<PreconditionResult> {
  const deployerHasRole = await hasRole(client, contractAddress, GOVERNOR_ROLE, deployer)

  if (!deployerHasRole) {
    return { done: true }
  }
  return { done: false, reason: 'deployer GOVERNOR_ROLE not revoked' }
}

/**
 * Check if ProxyAdmin ownership is transferred to governor
 *
 * Generic check used for any contract with an OZ v5 per-proxy ProxyAdmin.
 * Used by transfer scripts for IA, RAM, Reclaim, REO.
 */
export async function checkProxyAdminTransferred(
  client: PublicClient,
  proxyAdminAddress: string,
  governor: string,
): Promise<PreconditionResult> {
  const currentOwner = (await client.readContract({
    address: proxyAdminAddress as `0x${string}`,
    abi: OZ_PROXY_ADMIN_ABI,
    functionName: 'owner',
  })) as string

  if (currentOwner.toLowerCase() === governor.toLowerCase()) {
    return { done: true }
  }
  return { done: false, reason: `ProxyAdmin owned by ${currentOwner}, not governor` }
}
