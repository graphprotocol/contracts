import type { Environment } from '@rocketh/core/types'
import type { PublicClient } from 'viem'

import {
  ACCESS_CONTROL_ENUMERABLE_ABI,
  GRAPH_TOKEN_ABI,
  IERC165_ABI,
  IERC165_INTERFACE_ID,
  IISSUANCE_TARGET_INTERFACE_ID,
  REWARDS_ELIGIBILITY_ORACLE_ABI,
  REWARDS_MANAGER_ABI,
  REWARDS_MANAGER_DEPRECATED_ABI,
} from './abis.js'
import { getTargetChainIdFromEnv } from './address-book-utils.js'
import { getGovernor, getPauseGuardian } from './controller-utils.js'
import { graph } from '../rocketh/deploy.js'

/**
 * Check if a contract supports a specific interface via ERC165
 *
 * @param client - Viem public client
 * @param contractAddress - Contract address to check
 * @param interfaceId - Interface ID (4 bytes hex string like '0x01ffc9a7')
 * @returns true if interface is supported, false otherwise
 */
export async function supportsInterface(
  client: PublicClient,
  contractAddress: string,
  interfaceId: string,
): Promise<boolean> {
  try {
    const supported = await client.readContract({
      address: contractAddress as `0x${string}`,
      abi: IERC165_ABI,
      functionName: 'supportsInterface',
      args: [interfaceId as `0x${string}`],
    })
    return supported as boolean
  } catch {
    return false
  }
}

/**
 * Check if RewardsManager has been upgraded to support IIssuanceTarget
 *
 * The upgraded RewardsManager implements IERC165 and IIssuanceTarget interfaces.
 * This check verifies the upgrade by testing for IIssuanceTarget support.
 *
 * @param client - Viem public client
 * @param rmAddress - RewardsManager address
 * @returns true if upgraded, false otherwise
 */
export async function isRewardsManagerUpgraded(client: PublicClient, rmAddress: string): Promise<boolean> {
  return supportsInterface(client, rmAddress, IISSUANCE_TARGET_INTERFACE_ID)
}

/**
 * Require RewardsManager to be upgraded, exiting if not
 *
 * @param client - Viem public client
 * @param rmAddress - RewardsManager address
 * @param env - Deployment environment for showing messages
 * @exits 1 if RewardsManager has not been upgraded (expected prerequisite state)
 */
export async function requireRewardsManagerUpgraded(
  client: PublicClient,
  rmAddress: string,
  env: Environment,
): Promise<void> {
  const upgraded = await isRewardsManagerUpgraded(client, rmAddress)
  if (!upgraded) {
    env.showMessage(`\n❌ RewardsManager has not been upgraded yet`)
    env.showMessage(`   The on-chain RewardsManager does not support IERC165/IIssuanceTarget`)
    env.showMessage(`   Run: npx hardhat deploy:execute-governance --network ${env.name}`)
    env.showMessage(`   (This will execute the pending RewardsManager upgrade TX)\n`)
    process.exit(1)
  }
}

/**
 * Check IssuanceAllocator activation state
 *
 * Returns status of:
 * - Whether IA is set as issuanceAllocator on RewardsManager
 * - Whether IA has minter role on GraphToken
 */
export interface ActivationStatus {
  iaIntegrated: boolean
  iaMinter: boolean
  currentIssuanceAllocator: string
}

export async function checkIssuanceAllocatorActivation(
  client: PublicClient,
  iaAddress: string,
  rmAddress: string,
  gtAddress: string,
): Promise<ActivationStatus> {
  // Check RM.issuanceAllocator() == IA
  const currentIA = (await client.readContract({
    address: rmAddress as `0x${string}`,
    abi: REWARDS_MANAGER_ABI,
    functionName: 'getIssuanceAllocator',
  })) as string

  const iaIntegrated = currentIA.toLowerCase() === iaAddress.toLowerCase()

  // Check GraphToken.isMinter(IA)
  const iaMinter = (await client.readContract({
    address: gtAddress as `0x${string}`,
    abi: GRAPH_TOKEN_ABI,
    functionName: 'isMinter',
    args: [iaAddress as `0x${string}`],
  })) as boolean

  return {
    iaIntegrated,
    iaMinter,
    currentIssuanceAllocator: currentIA,
  }
}

/**
 * Check if IssuanceAllocator is fully activated
 *
 * @returns true if both integrated with RM and has minter role
 */
export async function isIssuanceAllocatorActivated(
  client: PublicClient,
  iaAddress: string,
  rmAddress: string,
  gtAddress: string,
): Promise<boolean> {
  const status = await checkIssuanceAllocatorActivation(client, iaAddress, rmAddress, gtAddress)
  return status.iaIntegrated && status.iaMinter
}

// Well-known reclaim reasons (bytes32)
// These correspond to the condition identifiers in RewardsCondition.sol (keccak256 of condition string)
// Each reason maps to a contract: ReclaimedRewardsFor<ReasonName>
export const RECLAIM_REASONS = {
  indexerIneligible: '0xfcadc72cad493def76767524554db9da829b6aca9457c0187f63000dba3c9439',
  subgraphDenied: '0xc0f4a5620db2f97e7c3a4ba7058497eaa0d497538b2666d66bd6932f25345c88',
  stalePoi: '0xe677423ace949fe7684efc4b33b0b10dc0f71b38c22370d74dad5ff6bec3e311',
  zeroPoi: '0xf067261e30ea99a11911c4e98249a1645a4870b3ef56b8aa8b8967e15a543095',
  closeAllocation: '0x3021a5ea86e7115dadc0819121dc2b1f58b45c2372d2e93b593567f0dd797df8',
} as const

// Mapping from reclaim reason keys to deployed contract names
export const RECLAIM_CONTRACT_NAMES = {
  indexerIneligible: 'ReclaimedRewardsForIndexerIneligible',
  subgraphDenied: 'ReclaimedRewardsForSubgraphDenied',
  stalePoi: 'ReclaimedRewardsForStalePoi',
  zeroPoi: 'ReclaimedRewardsForZeroPoi',
  closeAllocation: 'ReclaimedRewardsForCloseAllocation',
} as const

export type ReclaimReasonKey = keyof typeof RECLAIM_REASONS

/**
 * Get the reclaim address for a given reason from RewardsManager
 *
 * @param client - Viem public client
 * @param rmAddress - RewardsManager address
 * @param reason - The reason identifier (bytes32)
 * @returns The reclaim address for that reason, or null if not set or function doesn't exist
 */
export async function getReclaimAddress(
  client: PublicClient,
  rmAddress: string,
  reason: string,
): Promise<string | null> {
  try {
    const reclaimAddress = (await client.readContract({
      address: rmAddress as `0x${string}`,
      abi: REWARDS_MANAGER_ABI,
      functionName: 'getReclaimAddress',
      args: [reason as `0x${string}`],
    })) as string
    // Zero address means not set
    if (reclaimAddress === '0x0000000000000000000000000000000000000000') {
      return null
    }
    return reclaimAddress
  } catch {
    return null
  }
}

/**
 * Get issuancePerBlock from RewardsManager
 */
export async function getRewardsManagerRawIssuanceRate(client: PublicClient, rmAddress: string): Promise<bigint> {
  const rate = (await client.readContract({
    address: rmAddress as `0x${string}`,
    abi: REWARDS_MANAGER_DEPRECATED_ABI,
    functionName: 'issuancePerBlock',
  })) as bigint
  return rate
}

// ============================================================================
// RewardsEligibilityOracle Role Checks
// ============================================================================

/**
 * Result of checking OPERATOR_ROLE assignment on RewardsEligibilityOracle
 */
export interface OperatorRoleCheckResult {
  /** Whether the check passed (correct assignment state) */
  ok: boolean
  /** Number of addresses with OPERATOR_ROLE */
  count: number
  /** The expected operator address (null if not configured) */
  expectedOperator: string | null
  /** Actual role holders (if enumerable) */
  actualHolders: string[]
  /** Human-readable status message */
  message: string
}

/**
 * Check OPERATOR_ROLE assignment on RewardsEligibilityOracle
 *
 * This is the SINGLE authoritative check for OPERATOR_ROLE correctness.
 * Used by both deployment scripts and status checks.
 *
 * Rules:
 * - If expectedOperator is provided: exactly 1 holder, must be expectedOperator
 * - If expectedOperator is null: exactly 0 holders
 *
 * @param client - Viem public client
 * @param reoAddress - RewardsEligibilityOracle address
 * @param expectedOperator - Expected operator address (from address book), or null if not configured
 * @returns Check result with pass/fail status and details
 */
export async function checkOperatorRole(
  client: PublicClient,
  reoAddress: string,
  expectedOperator: string | null,
): Promise<OperatorRoleCheckResult> {
  // Get OPERATOR_ROLE constant
  const operatorRole = (await client.readContract({
    address: reoAddress as `0x${string}`,
    abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
    functionName: 'OPERATOR_ROLE',
  })) as `0x${string}`

  // Get role member count
  const count = Number(
    (await client.readContract({
      address: reoAddress as `0x${string}`,
      abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
      functionName: 'getRoleMemberCount',
      args: [operatorRole],
    })) as bigint,
  )

  // Get actual holders
  const actualHolders: string[] = []
  for (let i = 0; i < count; i++) {
    const holder = (await client.readContract({
      address: reoAddress as `0x${string}`,
      abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
      functionName: 'getRoleMember',
      args: [operatorRole, BigInt(i)],
    })) as string
    actualHolders.push(holder)
  }

  // Validate based on expected state
  if (expectedOperator === null) {
    // No operator configured - must have zero holders
    if (count === 0) {
      return {
        ok: true,
        count,
        expectedOperator,
        actualHolders,
        message: 'OPERATOR_ROLE: none assigned (NetworkOperator not configured)',
      }
    } else {
      return {
        ok: false,
        count,
        expectedOperator,
        actualHolders,
        message: `OPERATOR_ROLE: unexpected holders (${count}) when NetworkOperator not configured: ${actualHolders.join(', ')}`,
      }
    }
  } else {
    // Operator configured - must have exactly one holder matching expected
    if (count === 0) {
      return {
        ok: false,
        count,
        expectedOperator,
        actualHolders,
        message: `OPERATOR_ROLE: not assigned (expected ${expectedOperator})`,
      }
    } else if (count === 1 && actualHolders[0].toLowerCase() === expectedOperator.toLowerCase()) {
      return {
        ok: true,
        count,
        expectedOperator,
        actualHolders,
        message: `OPERATOR_ROLE: ${expectedOperator}`,
      }
    } else if (count === 1) {
      return {
        ok: false,
        count,
        expectedOperator,
        actualHolders,
        message: `OPERATOR_ROLE: wrong holder (expected ${expectedOperator}, got ${actualHolders[0]})`,
      }
    } else {
      return {
        ok: false,
        count,
        expectedOperator,
        actualHolders,
        message: `OPERATOR_ROLE: too many holders (${count}): ${actualHolders.join(', ')} (expected only ${expectedOperator})`,
      }
    }
  }
}

// ============================================================================
// Generic Configuration Condition Framework
// ============================================================================

/**
 * Format seconds as human-readable duration
 */
export function formatDuration(seconds: bigint | number): string {
  const secs = typeof seconds === 'bigint' ? Number(seconds) : seconds
  const days = secs / 86400
  if (Number.isInteger(days)) {
    return `${days} day${days === 1 ? '' : 's'}`
  }
  return `${days.toFixed(2)} days`
}

/**
 * A parameter condition - checks and sets a simple getter/setter value
 *
 * @template T - The type of the configuration value (e.g., bigint, string, boolean)
 */
export interface ParamCondition<T = bigint> {
  /** Condition type discriminator */
  type?: 'param'

  /** Condition name (used in messages and as identifier) */
  name: string

  /** Human-readable description */
  description: string

  /** ABI for contract reads/writes */
  abi: readonly unknown[]

  /** Function name to read current value */
  getter: string

  /** Function name to set new value */
  setter: string

  /** Target value for this condition */
  target: T

  /** Compare current to target (defaults to strict equality) */
  compare?: (current: T, target: T) => boolean

  /** Format value for display (defaults to String()) */
  format?: (value: T) => string
}

/**
 * A role condition - checks and grants/revokes a role for an account
 */
export interface RoleCondition {
  /** Condition type discriminator */
  type: 'role'

  /** Condition name (used in messages and as identifier) */
  name: string

  /** Human-readable description */
  description: string

  /** ABI for contract reads/writes */
  abi: readonly unknown[]

  /** Function name to get role bytes32 (e.g., 'PAUSE_ROLE') */
  roleGetter: string

  /** Account that should have/not have the role */
  targetAccount: string

  /** Action: grant (account should have role) or revoke (account should NOT have role) */
  action?: 'grant' | 'revoke'

  /** Format account for display (defaults to address) */
  formatAccount?: (address: string) => string
}

/**
 * A single configuration condition - either a param or role condition
 *
 * @template T - The type for param conditions (e.g., bigint, string, boolean)
 */
export type ConfigCondition<T = bigint> = ParamCondition<T> | RoleCondition

/**
 * Result of checking a single condition
 */
export interface ConditionCheckResult<T = bigint> {
  /** Condition name */
  name: string
  /** Whether current matches target */
  ok: boolean
  /** Current on-chain value */
  current: T
  /** Target value */
  target: T
  /** Human-readable status message */
  message: string
}

/**
 * Result of checking multiple conditions
 */
export interface ConfigurationStatus<T = bigint> {
  /** Individual condition results */
  conditions: ConditionCheckResult<T>[]
  /** Whether all conditions passed */
  allOk: boolean
}

/**
 * Check a single condition against on-chain state
 */
export async function checkCondition<T>(
  client: PublicClient,
  contractAddress: string,
  condition: ConfigCondition<T>,
): Promise<ConditionCheckResult<T | boolean>> {
  // Handle role conditions
  if (condition.type === 'role') {
    const role = (await client.readContract({
      address: contractAddress as `0x${string}`,
      abi: condition.abi,
      functionName: condition.roleGetter,
    })) as `0x${string}`

    const hasRole = (await client.readContract({
      address: contractAddress as `0x${string}`,
      abi: condition.abi,
      functionName: 'hasRole',
      args: [role, condition.targetAccount as `0x${string}`],
    })) as boolean

    const action = condition.action ?? 'grant'
    const formatAccount = condition.formatAccount ?? ((a) => a)

    // For grant: ok if hasRole=true. For revoke: ok if hasRole=false
    const ok = action === 'grant' ? hasRole : !hasRole
    const status = ok ? '✓' : action === 'grant' ? '✗ needs grant' : '✗ needs revoke'

    return {
      name: condition.name,
      ok,
      current: hasRole as T | boolean,
      target: (action === 'grant') as T | boolean,
      message: `${condition.description}: ${formatAccount(condition.targetAccount)} ${status}`,
    }
  }

  // Handle param conditions (default)
  const current = (await client.readContract({
    address: contractAddress as `0x${string}`,
    abi: condition.abi,
    functionName: condition.getter,
  })) as T

  const compare = condition.compare ?? ((a, b) => a === b)
  const format = condition.format ?? String

  const ok = compare(current, condition.target)
  const status = ok ? '✓' : '✗ needs update'

  return {
    name: condition.name,
    ok,
    current,
    target: condition.target,
    message: `${condition.description}: ${format(current)} [target: ${format(condition.target)}] ${status}`,
  }
}

/**
 * Check multiple conditions against on-chain state
 *
 * Use this for status checks outside of deploy mode.
 */
export async function checkConditions<T>(
  client: PublicClient,
  contractAddress: string,
  conditions: ConfigCondition<T>[],
): Promise<ConfigurationStatus<T | boolean>> {
  const results = await Promise.all(conditions.map((c) => checkCondition(client, contractAddress, c)))

  return {
    conditions: results,
    allOk: results.every((r) => r.ok),
  }
}

// ============================================================================
// RewardsEligibilityOracle Conditions
// ============================================================================

/** Default REO configuration values */
export const REO_DEFAULTS = {
  eligibilityPeriod: 14n * 24n * 60n * 60n, // 14 days
  oracleUpdateTimeout: 7n * 24n * 60n * 60n, // 7 days
} as const

/**
 * REO configuration conditions
 *
 * Reusable for both deploy-mode configuration and status checks.
 */
export function createREOParamConditions(
  targets: { eligibilityPeriod?: bigint; oracleUpdateTimeout?: bigint } = {},
): ParamCondition<bigint>[] {
  return [
    {
      name: 'eligibilityPeriod',
      description: 'Eligibility period',
      abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
      getter: 'getEligibilityPeriod',
      setter: 'setEligibilityPeriod',
      target: targets.eligibilityPeriod ?? REO_DEFAULTS.eligibilityPeriod,
      format: (v) => `${v} seconds (${formatDuration(v)})`,
    },
    {
      name: 'oracleUpdateTimeout',
      description: 'Oracle update timeout',
      abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
      getter: 'getOracleUpdateTimeout',
      setter: 'setOracleUpdateTimeout',
      target: targets.oracleUpdateTimeout ?? REO_DEFAULTS.oracleUpdateTimeout,
      format: (v) => `${v} seconds (${formatDuration(v)})`,
    },
  ]
}

/**
 * @deprecated Use createREOParamConditions for param-only or createREOConditions for all
 */
export const createREOConditions = createREOParamConditions

/**
 * REO role condition targets
 */
export interface REORoleTargets {
  /** Account to grant PAUSE_ROLE (pauseGuardian) */
  pauseGuardian: string
  /** Account to grant OPERATOR_ROLE (networkOperator) */
  networkOperator: string
  /** Account to grant GOVERNOR_ROLE (governor) */
  governor: string
}

/**
 * Create REO role conditions
 *
 * Returns conditions for granting:
 * - PAUSE_ROLE to pauseGuardian
 * - OPERATOR_ROLE to networkOperator
 * - GOVERNOR_ROLE to governor
 */
export function createREORoleConditions(targets: REORoleTargets): RoleCondition[] {
  return [
    {
      type: 'role',
      name: 'pauseRole',
      description: 'PAUSE_ROLE',
      abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
      roleGetter: 'PAUSE_ROLE',
      targetAccount: targets.pauseGuardian,
    },
    {
      type: 'role',
      name: 'operatorRole',
      description: 'OPERATOR_ROLE',
      abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
      roleGetter: 'OPERATOR_ROLE',
      targetAccount: targets.networkOperator,
    },
    {
      type: 'role',
      name: 'governorRole',
      description: 'GOVERNOR_ROLE',
      abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
      roleGetter: 'GOVERNOR_ROLE',
      targetAccount: targets.governor,
    },
  ]
}

/**
 * Create all REO conditions (params + roles)
 *
 * Low-level factory - prefer getREOConditions(env) which fetches targets automatically.
 */
export function createAllREOConditions(
  paramTargets: { eligibilityPeriod?: bigint; oracleUpdateTimeout?: bigint } = {},
  roleTargets: REORoleTargets,
): ConfigCondition<bigint>[] {
  return [...createREOParamConditions(paramTargets), ...createREORoleConditions(roleTargets)]
}

/**
 * Create REO deployer revoke condition
 *
 * Checks that deployer does NOT have GOVERNOR_ROLE (should be revoked).
 */
export function createREODeployerRevokeCondition(deployer: string): RoleCondition {
  return {
    type: 'role',
    name: 'deployerGovernorRoleRevoked',
    description: 'Deployer GOVERNOR_ROLE',
    abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
    roleGetter: 'GOVERNOR_ROLE',
    targetAccount: deployer,
    action: 'revoke',
  }
}

// ============================================================================
// REO Condition Fetchers (single source of truth)
// ============================================================================

/**
 * Get REO configuration conditions with targets fetched from environment
 *
 * This is the SINGLE SOURCE OF TRUTH for REO conditions.
 * Fetches governor, pauseGuardian, networkOperator automatically.
 *
 * Requires NetworkOperator to be configured in the issuance address book.
 */
export async function getREOConditions(env: Environment): Promise<ConfigCondition<bigint>[]> {
  const governor = await getGovernor(env)
  const pauseGuardian = await getPauseGuardian(env)
  const ab = graph.getIssuanceAddressBook(await getTargetChainIdFromEnv(env))

  const networkOperator = ab.entryExists('NetworkOperator') ? ab.getEntry('NetworkOperator')?.address : null
  if (!networkOperator) {
    env.showMessage('\n❌ NetworkOperator not configured in issuance address book')
    env.showMessage('   Add NetworkOperator to packages/issuance/addresses.json\n')
    process.exit(1)
  }

  return createAllREOConditions({}, { governor, pauseGuardian, networkOperator })
}

/**
 * Get REO transfer governance conditions (revoke deployer role)
 *
 * Single source of truth for transfer-governance step.
 */
export function getREOTransferGovernanceConditions(deployer: string): ConfigCondition<bigint>[] {
  return [createREODeployerRevokeCondition(deployer)]
}

// ============================================================================
// RewardsEligibilityOracle Role Checks
// ============================================================================

/**
 * Result of checking if an account has a specific role
 */
export interface RoleCheckResult {
  /** Whether the account has the role */
  hasRole: boolean
  /** The role being checked (bytes32) */
  role: `0x${string}`
  /** The account being checked */
  account: string
  /** Human-readable status message */
  message: string
}

/**
 * Check if an account has a specific role on RewardsEligibilityOracle
 */
export async function checkREORole(
  client: PublicClient,
  reoAddress: string,
  roleName: 'GOVERNOR_ROLE' | 'PAUSE_ROLE' | 'OPERATOR_ROLE' | 'ORACLE_ROLE',
  account: string,
): Promise<RoleCheckResult> {
  const role = (await client.readContract({
    address: reoAddress as `0x${string}`,
    abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
    functionName: roleName,
  })) as `0x${string}`

  const hasRole = (await client.readContract({
    address: reoAddress as `0x${string}`,
    abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
    functionName: 'hasRole',
    args: [role, account as `0x${string}`],
  })) as boolean

  return {
    hasRole,
    role,
    account,
    message: `${roleName}: ${hasRole ? '✓' : '✗'} (${account})`,
  }
}

// ============================================================================
// RewardsManager Integration Conditions
// ============================================================================

/**
 * Compare addresses (case-insensitive)
 */
export function addressEquals(a: string, b: string): boolean {
  return a.toLowerCase() === b.toLowerCase()
}

/**
 * Truncate address for display
 */
export function formatAddress(address: string): string {
  return `${address.slice(0, 6)}...${address.slice(-4)}`
}

/**
 * Create RewardsManager integration condition for REO
 *
 * Checks that RewardsManager.getRewardsEligibilityOracle() == reoAddress
 */
export function createRMIntegrationCondition(reoAddress: string): ParamCondition<string> {
  return {
    name: 'rewardsEligibilityOracle',
    description: 'RewardsEligibilityOracle',
    abi: REWARDS_MANAGER_ABI,
    getter: 'getRewardsEligibilityOracle',
    setter: 'setRewardsEligibilityOracle',
    target: reoAddress,
    compare: addressEquals,
    format: formatAddress,
  }
}

// ============================================================================
// Generic Role Enumeration (for any BaseUpgradeable contract)
// ============================================================================

/**
 * Information about a single role
 */
export interface RoleInfo {
  /** Role name (e.g., 'GOVERNOR_ROLE') */
  name: string
  /** Role bytes32 hash */
  role: `0x${string}`
  /** Admin role bytes32 hash */
  adminRole: `0x${string}`
  /** Number of members with this role */
  memberCount: number
  /** Addresses that hold this role */
  members: string[]
}

/**
 * Result of enumerating all roles for a contract
 */
export interface RoleEnumerationResult {
  /** Contract address */
  contractAddress: string
  /** All roles that were enumerated */
  roles: RoleInfo[]
  /** Roles that failed to read (may not exist on contract) */
  failedRoles: string[]
}

/**
 * Get the bytes32 value of a role constant from a contract
 *
 * @param client - Viem public client
 * @param contractAddress - Contract address
 * @param roleName - Name of the role constant (e.g., 'GOVERNOR_ROLE')
 * @returns The bytes32 role value, or null if the role doesn't exist
 */
export async function getRoleHash(
  client: PublicClient,
  contractAddress: string,
  roleName: string,
): Promise<`0x${string}` | null> {
  try {
    // Create a minimal ABI for reading the role constant
    const roleAbi = [
      {
        inputs: [],
        name: roleName,
        outputs: [{ type: 'bytes32' }],
        stateMutability: 'view',
        type: 'function',
      },
    ] as const

    const role = (await client.readContract({
      address: contractAddress as `0x${string}`,
      abi: roleAbi,
      functionName: roleName,
    })) as `0x${string}`

    return role
  } catch {
    return null
  }
}

/**
 * Enumerate all members of a role
 *
 * @param client - Viem public client
 * @param contractAddress - Contract address
 * @param role - Role bytes32 hash
 * @returns Array of member addresses
 */
export async function enumerateRoleMembers(
  client: PublicClient,
  contractAddress: string,
  role: `0x${string}`,
): Promise<string[]> {
  const count = Number(
    (await client.readContract({
      address: contractAddress as `0x${string}`,
      abi: ACCESS_CONTROL_ENUMERABLE_ABI,
      functionName: 'getRoleMemberCount',
      args: [role],
    })) as bigint,
  )

  const members: string[] = []
  for (let i = 0; i < count; i++) {
    const member = (await client.readContract({
      address: contractAddress as `0x${string}`,
      abi: ACCESS_CONTROL_ENUMERABLE_ABI,
      functionName: 'getRoleMember',
      args: [role, BigInt(i)],
    })) as string
    members.push(member)
  }

  return members
}

/**
 * Get full role information including admin and members
 *
 * @param client - Viem public client
 * @param contractAddress - Contract address
 * @param roleName - Name of the role constant (e.g., 'GOVERNOR_ROLE')
 * @returns RoleInfo or null if role doesn't exist
 */
export async function getRoleInfo(
  client: PublicClient,
  contractAddress: string,
  roleName: string,
): Promise<RoleInfo | null> {
  const role = await getRoleHash(client, contractAddress, roleName)
  if (!role) {
    return null
  }

  const adminRole = (await client.readContract({
    address: contractAddress as `0x${string}`,
    abi: ACCESS_CONTROL_ENUMERABLE_ABI,
    functionName: 'getRoleAdmin',
    args: [role],
  })) as `0x${string}`

  const members = await enumerateRoleMembers(client, contractAddress, role)

  return {
    name: roleName,
    role,
    adminRole,
    memberCount: members.length,
    members,
  }
}

/**
 * Enumerate all roles for a contract
 *
 * @param client - Viem public client
 * @param contractAddress - Contract address
 * @param roleNames - Array of role constant names to check
 * @returns RoleEnumerationResult with all role info
 */
export async function enumerateContractRoles(
  client: PublicClient,
  contractAddress: string,
  roleNames: readonly string[],
): Promise<RoleEnumerationResult> {
  const roles: RoleInfo[] = []
  const failedRoles: string[] = []

  for (const roleName of roleNames) {
    const info = await getRoleInfo(client, contractAddress, roleName)
    if (info) {
      roles.push(info)
    } else {
      failedRoles.push(roleName)
    }
  }

  return {
    contractAddress,
    roles,
    failedRoles,
  }
}

/**
 * Check if an account has the admin role for a given role
 *
 * @param client - Viem public client
 * @param contractAddress - Contract address
 * @param role - Role bytes32 hash
 * @param account - Account to check
 * @returns true if account is an admin for the role
 */
export async function hasAdminRole(
  client: PublicClient,
  contractAddress: string,
  role: `0x${string}`,
  account: string,
): Promise<boolean> {
  const adminRole = (await client.readContract({
    address: contractAddress as `0x${string}`,
    abi: ACCESS_CONTROL_ENUMERABLE_ABI,
    functionName: 'getRoleAdmin',
    args: [role],
  })) as `0x${string}`

  const hasRole = (await client.readContract({
    address: contractAddress as `0x${string}`,
    abi: ACCESS_CONTROL_ENUMERABLE_ABI,
    functionName: 'hasRole',
    args: [adminRole, account as `0x${string}`],
  })) as boolean

  return hasRole
}

/**
 * Check if an account already has a specific role
 *
 * @param client - Viem public client
 * @param contractAddress - Contract address
 * @param role - Role bytes32 hash
 * @param account - Account to check
 * @returns true if account has the role
 */
export async function accountHasRole(
  client: PublicClient,
  contractAddress: string,
  role: `0x${string}`,
  account: string,
): Promise<boolean> {
  const hasRole = (await client.readContract({
    address: contractAddress as `0x${string}`,
    abi: ACCESS_CONTROL_ENUMERABLE_ABI,
    functionName: 'hasRole',
    args: [role, account as `0x${string}`],
  })) as boolean

  return hasRole
}

/**
 * Get admin role info for a given role
 *
 * @param client - Viem public client
 * @param contractAddress - Contract address
 * @param role - Role bytes32 hash
 * @param knownRoles - Known roles for name resolution
 * @returns Admin role hash and name (if known)
 */
export async function getAdminRoleInfo(
  client: PublicClient,
  contractAddress: string,
  role: `0x${string}`,
  knownRoles: RoleInfo[],
): Promise<{ adminRole: `0x${string}`; adminRoleName: string | null; adminMembers: string[] }> {
  const adminRole = (await client.readContract({
    address: contractAddress as `0x${string}`,
    abi: ACCESS_CONTROL_ENUMERABLE_ABI,
    functionName: 'getRoleAdmin',
    args: [role],
  })) as `0x${string}`

  const adminRoleName = knownRoles.find((r) => r.role === adminRole)?.name ?? null
  const adminMembers = await enumerateRoleMembers(client, contractAddress, adminRole)

  return { adminRole, adminRoleName, adminMembers }
}
