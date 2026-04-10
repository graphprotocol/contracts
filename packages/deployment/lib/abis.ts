/**
 * Shared ABI definitions for contract interactions
 *
 * Generated ABIs are produced by `pnpm generate:abis` from contract artifacts.
 * The contract registry drives which ABIs and interface IDs are generated.
 * Only ACCESS_CONTROL_ENUMERABLE_ABI is hand-maintained (generic role queries).
 */

// Re-export all generated typed ABIs, aliases, and interface IDs
export {
  CONTROLLER_ABI,
  DIRECT_ALLOCATION_ABI,
  GRAPH_PROXY_ADMIN_ABI,
  GRAPH_TOKEN_ABI,
  IERC165_ABI,
  IERC165_INTERFACE_ID,
  IISSUANCE_TARGET_INTERFACE_ID,
  INITIALIZE_GOVERNOR_ABI,
  IREWARDS_MANAGER_INTERFACE_ID,
  ISSUANCE_ALLOCATOR_ABI,
  ISSUANCE_TARGET_ABI,
  OZ_PROXY_ADMIN_ABI,
  PROVIDER_ELIGIBILITY_MANAGEMENT_ABI,
  REWARDS_ELIGIBILITY_ORACLE_ABI,
  REWARDS_MANAGER_ABI,
  REWARDS_MANAGER_DEPRECATED_ABI,
  SET_TARGET_ALLOCATION_ABI,
} from './generated/abis.js'

// ============================================================================
// Hand-rolled minimal ABIs (not in @graphprotocol/interfaces)
// ============================================================================

/**
 * Minimal ABI for RecurringCollector pause guardian management
 *
 * RC's pause guardian functions are not part of an interface in
 * @graphprotocol/interfaces. Used by RC configure and the GIP-0088 upgrade
 * batch to manage `setPauseGuardian` / `pauseGuardians`.
 */
export const RECURRING_COLLECTOR_PAUSE_ABI = [
  {
    inputs: [{ name: '_pauseGuardian', type: 'address' }],
    name: 'pauseGuardians',
    outputs: [{ type: 'bool' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      { name: '_pauseGuardian', type: 'address' },
      { name: '_allowed', type: 'bool' },
    ],
    name: 'setPauseGuardian',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
] as const

/**
 * Minimal ABI for SubgraphService allocation close guard
 *
 * `blockClosingAllocationWithActiveAgreement` is part of the SS interface but
 * not generated yet. Used by `GIP-0088:issuance-close-guard` and the goal
 * status display.
 */
export const SUBGRAPH_SERVICE_CLOSE_GUARD_ABI = [
  {
    inputs: [],
    name: 'getBlockClosingAllocationWithActiveAgreement',
    outputs: [{ type: 'bool' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'enabled', type: 'bool' }],
    name: 'setBlockClosingAllocationWithActiveAgreement',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
] as const

// ============================================================================
// Generic ABIs for role enumeration
// ============================================================================

/**
 * Minimal ABI for AccessControlEnumerable role queries and management
 * Works with any contract inheriting from OZ AccessControlEnumerableUpgradeable
 */
export const ACCESS_CONTROL_ENUMERABLE_ABI = [
  // View functions
  {
    inputs: [{ name: 'role', type: 'bytes32' }],
    name: 'getRoleMemberCount',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      { name: 'role', type: 'bytes32' },
      { name: 'index', type: 'uint256' },
    ],
    name: 'getRoleMember',
    outputs: [{ type: 'address' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      { name: 'role', type: 'bytes32' },
      { name: 'account', type: 'address' },
    ],
    name: 'hasRole',
    outputs: [{ type: 'bool' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'role', type: 'bytes32' }],
    name: 'getRoleAdmin',
    outputs: [{ type: 'bytes32' }],
    stateMutability: 'view',
    type: 'function',
  },
  // Write functions (require admin role)
  {
    inputs: [
      { name: 'role', type: 'bytes32' },
      { name: 'account', type: 'address' },
    ],
    name: 'grantRole',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [
      { name: 'role', type: 'bytes32' },
      { name: 'account', type: 'address' },
    ],
    name: 'revokeRole',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
] as const
