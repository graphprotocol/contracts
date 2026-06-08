/**
 * Contract Registry - Single source of truth for contract metadata
 *
 * This module consolidates all contract metadata that was previously scattered
 * across sync scripts, deploy scripts, and utility functions.
 *
 * The registry is namespaced by address book to prevent key collisions when
 * the same contract name appears in multiple address books.
 */

import { ComponentTags } from './deployment-tags.js'

/**
 * Artifact source configuration - where to load contract ABI and bytecode from
 */
export type ArtifactSource =
  | { type: 'contracts'; path: string; name: string }
  | { type: 'subgraph-service'; name: string }
  | { type: 'horizon'; path: string }
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
 * Interface ABI configuration for typed ABI generation.
 * Maps an export name to an interface in @graphprotocol/interfaces.
 */
export interface InterfaceAbiConfig {
  /** Export name for the generated ABI constant (e.g. 'REWARDS_MANAGER_ABI') */
  name: string
  /** Interface name in @graphprotocol/interfaces artifacts (e.g. 'IRewardsManager') */
  interface: string
}

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

  /**
   * Component tag for deployment lifecycle management.
   * Used by script factories to derive action tags (deploy, upgrade, etc.)
   * and dependencies without per-script boilerplate.
   *
   * Must match the PascalCase contract name in deployment-tags.ts ComponentTags.
   * Example: 'PaymentsEscrow' → tags: 'PaymentsEscrow:upgrade', deps: 'PaymentsEscrow:deploy'
   *
   * Multiple contracts may share a componentTag when they form a single
   * deployment unit (e.g., REO A/B instances share 'RewardsEligibility').
   */
  componentTag?: string

  /**
   * Lifecycle actions available for this component beyond the standard deploy+upgrade.
   * Used by status modules to show available `--tags` actions.
   *
   * When omitted, defaults to ['deploy', 'upgrade'] for deployable proxy contracts,
   * or ['deploy'] for non-proxy deployable contracts.
   * Always includes 'all' implicitly.
   */
  lifecycleActions?: readonly string[]

  /**
   * Interface ABIs to generate for this contract.
   * Used by the ABI codegen script to produce typed `as const` exports.
   * Each entry maps to an interface artifact in @graphprotocol/interfaces.
   * The codegen also extracts the interfaceId from the factory class.
   */
  interfaces?: readonly InterfaceAbiConfig[]

  /**
   * Generate a typed ABI from the contract's full artifact.
   * Value is the export name (e.g. 'ISSUANCE_ALLOCATOR_ABI').
   * Requires `artifact` to be set on this entry.
   */
  generateAbi?: string

  /**
   * Name of the shared implementation entry when this proxy uses an
   * implementation deployed separately (e.g. DirectAllocation_Implementation).
   *
   * Used by the upgrade pipeline to auto-detect when the shared implementation
   * has been redeployed and set pendingImplementation accordingly.
   */
  sharedImplementation?: string
}

// ============================================================================
// Horizon Contracts
// ============================================================================

const HORIZON_CONTRACTS = {
  RewardsManager: {
    artifact: { type: 'contracts', path: 'rewards', name: 'RewardsManager' },
    interfaces: [
      { name: 'REWARDS_MANAGER_ABI', interface: 'IRewardsManager' },
      { name: 'REWARDS_MANAGER_DEPRECATED_ABI', interface: 'IRewardsManagerDeprecated' },
      { name: 'PROVIDER_ELIGIBILITY_MANAGEMENT_ABI', interface: 'IProviderEligibilityManagement' },
    ],
    proxyType: 'graph',
    proxyAdminName: 'GraphProxyAdmin',
    prerequisite: true,
    deployable: true,
    componentTag: ComponentTags.REWARDS_MANAGER,
    lifecycleActions: ['deploy', 'upgrade'],
  },
  GraphProxyAdmin: {
    interfaces: [{ name: 'GRAPH_PROXY_ADMIN_ABI', interface: 'IGraphProxyAdmin' }],
    prerequisite: true,
  },
  L2GraphToken: {
    artifact: { type: 'contracts', path: 'l2/token', name: 'L2GraphToken' },
    interfaces: [{ name: 'GRAPH_TOKEN_ABI', interface: 'IGraphToken' }],
    prerequisite: true,
  },
  Controller: {
    interfaces: [{ name: 'CONTROLLER_ABI', interface: 'IControllerToolshed' }],
    prerequisite: true,
  },
  GraphTallyCollector: {
    prerequisite: true,
  },
  RecurringCollector: {
    artifact: { type: 'horizon', path: 'contracts/payments/collectors/RecurringCollector.sol/RecurringCollector' },
    proxyType: 'transparent',
    deployable: true,
    componentTag: ComponentTags.RECURRING_COLLECTOR,
    lifecycleActions: ['deploy', 'upgrade', 'configure', 'transfer'],
  },
  L2Curation: {
    artifact: { type: 'contracts', path: 'l2/curation', name: 'L2Curation' },
    proxyType: 'graph',
    proxyAdminName: 'GraphProxyAdmin',
    prerequisite: true,
    deployable: true,
    componentTag: ComponentTags.L2_CURATION,
  },
  HorizonStaking: {
    artifact: { type: 'horizon', path: 'contracts/staking/HorizonStaking.sol/HorizonStaking' },
    proxyType: 'graph',
    proxyAdminName: 'GraphProxyAdmin',
    prerequisite: true,
    deployable: true,
    componentTag: ComponentTags.HORIZON_STAKING,
  },
  GraphPayments: {
    prerequisite: true,
  },
  PaymentsEscrow: {
    artifact: { type: 'horizon', path: 'contracts/payments/PaymentsEscrow.sol/PaymentsEscrow' },
    proxyType: 'transparent',
    prerequisite: true,
    deployable: true,
    componentTag: ComponentTags.PAYMENTS_ESCROW,
  },
  // Contracts deployed by other systems (placeholders for address book type completeness)
  EpochManager: {},
  L2GNS: {},
  L2GraphTokenGateway: {},
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
    deployable: true,
    componentTag: ComponentTags.DISPUTE_MANAGER,
  },
  SubgraphService: {
    artifact: { type: 'subgraph-service', name: 'SubgraphService' },
    proxyType: 'transparent',
    // proxyAdminName omitted - auto-generates as SubgraphService_ProxyAdmin
    prerequisite: true,
    deployable: true,
    componentTag: ComponentTags.SUBGRAPH_SERVICE,
    lifecycleActions: ['deploy', 'upgrade', 'configure'],
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
// a per-proxy ProxyAdmin in the constructor. The deployer is the initial ProxyAdmin
// owner to allow post-deployment configuration; ownership is transferred to the
// protocol governor in the transfer-governance step. The ProxyAdmin address is stored
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
    generateAbi: 'ISSUANCE_ALLOCATOR_ABI',
    proxyType: 'transparent',
    // Per-proxy ProxyAdmin - address stored in address book entry's proxyAdmin field
    deployable: true,
    roles: BASE_ROLES,
    componentTag: ComponentTags.ISSUANCE_ALLOCATOR,
    lifecycleActions: ['deploy', 'upgrade', 'configure', 'transfer'],
  },
  RecurringAgreementManager: {
    artifact: {
      type: 'issuance',
      path: 'contracts/agreement/RecurringAgreementManager.sol/RecurringAgreementManager',
    },
    proxyType: 'transparent',
    deployable: true,
    roles: [...BASE_ROLES, 'DATA_SERVICE_ROLE', 'COLLECTOR_ROLE', 'AGREEMENT_MANAGER_ROLE'] as const,
    componentTag: ComponentTags.RECURRING_AGREEMENT_MANAGER,
    lifecycleActions: ['deploy', 'upgrade', 'configure', 'transfer'],
  },
  // A/B instances of RewardsEligibilityOracle - both share the same contract artifact
  // but deploy as independent proxies. Only one is active (integrated with RewardsManager) at a time.
  RewardsEligibilityOracleA: {
    artifact: { type: 'issuance', path: 'contracts/eligibility/RewardsEligibilityOracle.sol/RewardsEligibilityOracle' },
    generateAbi: 'REWARDS_ELIGIBILITY_ORACLE_ABI',
    proxyType: 'transparent',
    deployable: true,
    roles: [...BASE_ROLES, 'ORACLE_ROLE'] as const,
    componentTag: ComponentTags.REWARDS_ELIGIBILITY_A,
    // Integration with RewardsManager is a goal-level activation
    // (--tags GIP-0088:eligibility-integrate), not a per-component lifecycle action.
    lifecycleActions: ['deploy', 'upgrade', 'configure', 'transfer'],
  },
  RewardsEligibilityOracleB: {
    artifact: { type: 'issuance', path: 'contracts/eligibility/RewardsEligibilityOracle.sol/RewardsEligibilityOracle' },
    proxyType: 'transparent',
    deployable: true,
    roles: [...BASE_ROLES, 'ORACLE_ROLE'] as const,
    componentTag: ComponentTags.REWARDS_ELIGIBILITY_B,
    lifecycleActions: ['deploy', 'upgrade', 'configure', 'transfer'],
  },
  // Testnet mock REO - indexers control own eligibility, upgradeable for deployment consistency
  RewardsEligibilityOracleMock: {
    artifact: {
      type: 'issuance',
      path: 'contracts/eligibility/mocks/MockRewardsEligibilityOracle.sol/MockRewardsEligibilityOracle',
    },
    proxyType: 'transparent',
    deployable: true,
    roles: BASE_ROLES,
    componentTag: ComponentTags.REWARDS_ELIGIBILITY_MOCK,
    lifecycleActions: ['deploy', 'upgrade', 'transfer', 'integrate'],
  },
  DirectAllocation_Implementation: {
    artifact: { type: 'issuance', path: 'contracts/allocate/DirectAllocation.sol/DirectAllocation' },
    generateAbi: 'DIRECT_ALLOCATION_ABI',
    deployable: true,
    roles: BASE_ROLES,
    componentTag: ComponentTags.DIRECT_ALLOCATION_IMPL,
  },
  // Default target for IA — safety net for unallocated issuance
  // Uses DirectAllocation implementation (per-proxy ProxyAdmin)
  DefaultAllocation: {
    proxyType: 'transparent',
    sharedImplementation: 'DirectAllocation_Implementation',
    deployable: true,
    roles: BASE_ROLES,
    componentTag: ComponentTags.DEFAULT_ALLOCATION,
    lifecycleActions: ['deploy', 'upgrade', 'configure', 'transfer'],
  },
  // Default reclaim address — receives reclaimed rewards for all reasons
  // Uses DirectAllocation implementation (per-proxy ProxyAdmin)
  ReclaimedRewards: {
    proxyType: 'transparent',
    sharedImplementation: 'DirectAllocation_Implementation',
    deployable: true,
    roles: BASE_ROLES,
    componentTag: ComponentTags.REWARDS_RECLAIM,
    lifecycleActions: ['deploy', 'upgrade', 'configure', 'transfer'],
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
