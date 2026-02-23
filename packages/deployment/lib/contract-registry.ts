/**
 * Contract Registry - Single source of truth for contract metadata
 *
 * This module consolidates all contract metadata that was previously scattered
 * across sync scripts, deploy scripts, and utility functions.
 *
 * The registry is namespaced by address book to prevent key collisions when
 * the same contract name appears in multiple address books.
 */

/**
 * Artifact source configuration - where to load contract ABI and bytecode from
 */
export type ArtifactSource =
  | { type: 'contracts'; path: string; name: string }
  | { type: 'subgraph-service'; name: string }
  | { type: 'issuance'; path: string }
  | { type: 'openzeppelin'; name: string }

/**
 * Proxy pattern types
 * - 'graph': Graph Protocol's custom proxy (upgrade + acceptProxy via GraphProxyAdmin)
 * - 'transparent': OpenZeppelin TransparentUpgradeableProxy (upgradeAndCall via ProxyAdmin)
 * - undefined: Not a proxy contract
 */
export type ProxyType = 'graph' | 'transparent'

/**
 * Address book types - which address book a contract belongs to
 */
export type AddressBookType = 'horizon' | 'subgraph-service' | 'issuance'

/**
 * Contract metadata specification
 * Note: addressBook is no longer a field - it's implied by the registry namespace
 */
export interface ContractMetadata {
  /** Address book entry name (if different from registry key) */
  addressBookName?: string

  /** Artifact source for loading ABI and bytecode */
  artifact?: ArtifactSource

  /** Proxy type if this is a proxied contract */
  proxyType?: ProxyType

  /** Name of the proxy admin deployment record */
  proxyAdminName?: string

  /** If true, contract must exist on-chain (for sync prerequisite check) */
  prerequisite?: boolean

  /**
   * If true, contract is deployable by this system
   * If false/undefined, contract is managed elsewhere (prerequisite or placeholder)
   * Default: false (must explicitly opt-in)
   */
  deployable?: boolean

  /**
   * If true, entry is an address-only placeholder (code not required)
   * Use for entries that may be EOA or contract - sync skips bytecode verification.
   */
  addressOnly?: boolean

  /**
   * Role constants exposed by the contract (for role enumeration)
   * Array of function names that return bytes32 role constants (e.g., 'GOVERNOR_ROLE')
   * Used by roles:list task to enumerate role holders.
   */
  roles?: readonly string[]
}

// ============================================================================
// Horizon Contracts
// ============================================================================

const HORIZON_CONTRACTS = {
  RewardsManager: {
    artifact: { type: 'contracts', path: 'rewards', name: 'RewardsManager' },
    proxyType: 'graph',
    proxyAdminName: 'GraphProxyAdmin',
    prerequisite: true,
    deployable: true,
  },
  GraphProxyAdmin: {
    prerequisite: true,
  },
  L2GraphToken: {
    artifact: { type: 'contracts', path: 'l2/token', name: 'L2GraphToken' },
    prerequisite: true,
  },
  Controller: {
    prerequisite: true,
  },
  GraphTallyCollector: {
    prerequisite: true,
  },
  L2Curation: {
    prerequisite: true,
  },
  // Contracts deployed by other systems (placeholders for address book type completeness)
  EpochManager: {},
  GraphPayments: {},
  HorizonStaking: {},
  L2GNS: {},
  L2GraphTokenGateway: {},
  PaymentsEscrow: {},
  SubgraphNFT: {},
} as const satisfies Record<string, ContractMetadata>

// ============================================================================
// SubgraphService Contracts
// ============================================================================

// NOTE: SubgraphService contracts are deployed via Ignition with contract-specific proxy admins.
// The proxy admin address is stored inline in each contract's address book entry (proxyAdmin field).
// During sync, deployment records are auto-generated as `${contractName}_ProxyAdmin`.
const SUBGRAPH_SERVICE_CONTRACTS = {
  DisputeManager: {
    artifact: { type: 'subgraph-service', name: 'DisputeManager' },
    proxyType: 'transparent',
    // proxyAdminName omitted - auto-generates as DisputeManager_ProxyAdmin
    prerequisite: true,
  },
  SubgraphService: {
    artifact: { type: 'subgraph-service', name: 'SubgraphService' },
    proxyType: 'transparent',
    // proxyAdminName omitted - auto-generates as SubgraphService_ProxyAdmin
    prerequisite: true,
    deployable: true,
  },
  // Contracts deployed by other systems (placeholders for address book type completeness)
  // These exist in the subgraph-service address book but are managed elsewhere
  L2Curation: {},
  L2GNS: {},
  SubgraphNFT: {},
  LegacyDisputeManager: {},
  LegacyServiceRegistry: {},
} as const satisfies Record<string, ContractMetadata>

// ============================================================================
// Issuance Contracts
// ============================================================================

// NOTE: Issuance contracts use OZ v5 TransparentUpgradeableProxy which creates
// a per-proxy ProxyAdmin in the constructor. The ProxyAdmin address is stored
// inline in each contract's address book entry (proxyAdmin field), similar to
// subgraph-service contracts.

// Base roles from BaseUpgradeable - all issuance contracts inherit these
const BASE_ROLES = ['GOVERNOR_ROLE', 'PAUSE_ROLE', 'OPERATOR_ROLE'] as const

const ISSUANCE_CONTRACTS = {
  // Address placeholder for network operator (may be EOA or contract)
  // Used by deployment scripts to grant OPERATOR_ROLE
  NetworkOperator: { addressOnly: true },

  IssuanceAllocator: {
    artifact: { type: 'issuance', path: 'contracts/allocate/IssuanceAllocator.sol/IssuanceAllocator' },
    proxyType: 'transparent',
    // Per-proxy ProxyAdmin - address stored in address book entry's proxyAdmin field
    deployable: true,
    roles: BASE_ROLES,
  },
  PilotAllocation: {
    artifact: { type: 'issuance', path: 'contracts/allocate/PilotAllocation.sol/PilotAllocation' },
    proxyType: 'transparent',
    deployable: true,
    roles: BASE_ROLES,
  },
  RewardsEligibilityOracle: {
    artifact: { type: 'issuance', path: 'contracts/eligibility/RewardsEligibilityOracle.sol/RewardsEligibilityOracle' },
    proxyType: 'transparent',
    deployable: true,
    roles: [...BASE_ROLES, 'ORACLE_ROLE'] as const,
  },
  DirectAllocation_Implementation: {
    artifact: { type: 'issuance', path: 'contracts/allocate/DirectAllocation.sol/DirectAllocation' },
    deployable: true,
    roles: BASE_ROLES,
  },
  // Reclaim addresses for different reward reclaim reasons
  // All share DirectAllocation implementation (per-proxy ProxyAdmin for each)
  ReclaimedRewardsForIndexerIneligible: {
    proxyType: 'transparent',
    deployable: true,
    roles: BASE_ROLES,
  },
  ReclaimedRewardsForSubgraphDenied: {
    proxyType: 'transparent',
    deployable: true,
    roles: BASE_ROLES,
  },
  ReclaimedRewardsForStalePoi: {
    proxyType: 'transparent',
    deployable: true,
    roles: BASE_ROLES,
  },
  ReclaimedRewardsForZeroPoi: {
    proxyType: 'transparent',
    deployable: true,
    roles: BASE_ROLES,
  },
  ReclaimedRewardsForCloseAllocation: {
    proxyType: 'transparent',
    deployable: true,
    roles: BASE_ROLES,
  },
} as const satisfies Record<string, ContractMetadata>

// ============================================================================
// Namespaced Registry
// ============================================================================

/**
 * Contract registry namespaced by address book
 * This prevents key collisions when the same contract name appears in multiple address books
 */
export const CONTRACT_REGISTRY = {
  horizon: HORIZON_CONTRACTS,
  'subgraph-service': SUBGRAPH_SERVICE_CONTRACTS,
  issuance: ISSUANCE_CONTRACTS,
} as const

// Type helpers for the namespaced registry
export type HorizonContractName = keyof typeof HORIZON_CONTRACTS
export type SubgraphServiceContractName = keyof typeof SUBGRAPH_SERVICE_CONTRACTS
export type IssuanceContractName = keyof typeof ISSUANCE_CONTRACTS

/**
 * Registry entry with contract name and address book embedded
 */
export interface RegistryEntry extends ContractMetadata {
  name: string
  addressBook: AddressBookType
}

/**
 * Contract registry entries namespaced by address book
 * Use these to pass to deployment functions with full context
 *
 * @example
 * ```typescript
 * await upgradeImplementation(env, Contracts.horizon.RewardsManager)
 * await upgradeImplementation(env, Contracts['subgraph-service'].SubgraphService)
 * ```
 */
export const Contracts = {
  horizon: Object.entries(HORIZON_CONTRACTS).reduce(
    (acc, [name, metadata]) => {
      acc[name as HorizonContractName] = { name, addressBook: 'horizon', ...metadata }
      return acc
    },
    {} as Record<HorizonContractName, RegistryEntry>,
  ),
  'subgraph-service': Object.entries(SUBGRAPH_SERVICE_CONTRACTS).reduce(
    (acc, [name, metadata]) => {
      acc[name as SubgraphServiceContractName] = { name, addressBook: 'subgraph-service', ...metadata }
      return acc
    },
    {} as Record<SubgraphServiceContractName, RegistryEntry>,
  ),
  issuance: Object.entries(ISSUANCE_CONTRACTS).reduce(
    (acc, [name, metadata]) => {
      acc[name as IssuanceContractName] = { name, addressBook: 'issuance', ...metadata }
      return acc
    },
    {} as Record<IssuanceContractName, RegistryEntry>,
  ),
} as const

/**
 * Get contract metadata by address book and name
 */
export function getContractMetadata(addressBook: AddressBookType, name: string): ContractMetadata | undefined {
  const bookRegistry = CONTRACT_REGISTRY[addressBook]
  return bookRegistry[name as keyof typeof bookRegistry]
}

/**
 * Get the address book entry name for a contract
 * Falls back to the contract name if no override is specified
 */
export function getAddressBookEntryName(addressBook: AddressBookType, name: string): string {
  const metadata = getContractMetadata(addressBook, name)
  return metadata?.addressBookName ?? name
}

/**
 * Get all contracts for a specific address book
 */
export function getContractsByAddressBook(addressBook: AddressBookType): Array<[string, ContractMetadata]> {
  const bookRegistry = CONTRACT_REGISTRY[addressBook]
  return Object.entries(bookRegistry)
}

/**
 * List of proxied issuance contracts (for sync dynamic handling)
 */
export const PROXIED_ISSUANCE_CONTRACTS = Object.entries(ISSUANCE_CONTRACTS)
  .filter(([_, meta]) => 'proxyType' in meta && meta.proxyType === 'transparent')
  .map(([name]) => name)
