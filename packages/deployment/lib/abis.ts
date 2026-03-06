/**
 * Shared ABI definitions for contract interactions
 *
 * These ABIs are loaded from @graphprotocol/interfaces artifacts to ensure they stay in sync
 * with the actual contract interfaces. The interfaces package is the canonical source for ABIs.
 */

import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import type { Abi } from 'viem'

const require = createRequire(import.meta.url)

// Helper to load ABI from interface artifact
function loadAbi(artifactPath: string): Abi {
  const artifact = JSON.parse(readFileSync(require.resolve(artifactPath), 'utf-8'))
  return artifact.abi as Abi
}

// Interface IDs - these match the generated values from TypeChain factories
// Verified by tests: packages/issuance/testing/tests/allocate/InterfaceIdStability.test.ts
// and packages/contracts-test/tests/unit/rewards/rewards-interface.test.ts
export const IERC165_INTERFACE_ID = '0x01ffc9a7' as const
export const IISSUANCE_TARGET_INTERFACE_ID = '0xaee4dc43' as const
export const IREWARDS_MANAGER_INTERFACE_ID = '0x36b70adb' as const

export const REWARDS_MANAGER_ABI = loadAbi(
  '@graphprotocol/interfaces/artifacts/contracts/contracts/rewards/IRewardsManager.sol/IRewardsManager.json',
)

// Deprecated interface includes legacy functions like issuancePerBlock()
export const REWARDS_MANAGER_DEPRECATED_ABI = loadAbi(
  '@graphprotocol/interfaces/artifacts/contracts/contracts/rewards/IRewardsManagerDeprecated.sol/IRewardsManagerDeprecated.json',
)

export const CONTROLLER_ABI = loadAbi(
  '@graphprotocol/interfaces/artifacts/contracts/toolshed/IControllerToolshed.sol/IControllerToolshed.json',
)

// Core interfaces
export const GRAPH_TOKEN_ABI = loadAbi(
  '@graphprotocol/interfaces/artifacts/contracts/contracts/token/IGraphToken.sol/IGraphToken.json',
)

export const GRAPH_PROXY_ADMIN_ABI = loadAbi(
  '@graphprotocol/interfaces/artifacts/contracts/contracts/upgrades/IGraphProxyAdmin.sol/IGraphProxyAdmin.json',
)

export const IERC165_ABI = loadAbi(
  '@graphprotocol/interfaces/artifacts/@openzeppelin/contracts/introspection/IERC165.sol/IERC165.json',
)

// Issuance interfaces
export const ISSUANCE_TARGET_ABI = loadAbi(
  '@graphprotocol/interfaces/artifacts/contracts/issuance/allocate/IIssuanceTarget.sol/IIssuanceTarget.json',
)

// --- ABIs loaded from @graphprotocol/horizon (OZ contracts) ---
// These are not in interfaces package, load from horizon build

export const OZ_PROXY_ADMIN_ABI = loadAbi(
  '@graphprotocol/horizon/artifacts/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol/ProxyAdmin.json',
)

// --- ABIs loaded from @graphprotocol/issuance ---
// Full contract ABIs for deployment operations that need access to all methods

export const ISSUANCE_ALLOCATOR_ABI = loadAbi(
  '@graphprotocol/issuance/artifacts/contracts/allocate/IssuanceAllocator.sol/IssuanceAllocator.json',
)

export const DIRECT_ALLOCATION_ABI = loadAbi(
  '@graphprotocol/issuance/artifacts/contracts/allocate/DirectAllocation.sol/DirectAllocation.json',
)

export const REWARDS_ELIGIBILITY_ORACLE_ABI = loadAbi(
  '@graphprotocol/issuance/artifacts/contracts/eligibility/RewardsEligibilityOracle.sol/RewardsEligibilityOracle.json',
)

// Convenience re-exports for specific function subsets
// These reference the full ABIs above - viem will find the right function by name
export { ISSUANCE_ALLOCATOR_ABI as SET_TARGET_ALLOCATION_ABI }
export { DIRECT_ALLOCATION_ABI as INITIALIZE_GOVERNOR_ABI }

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
