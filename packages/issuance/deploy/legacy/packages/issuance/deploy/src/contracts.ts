import type { Contract } from 'ethers'
import * as path from 'path'

/**
 * Simple contract list type for generic contract collections
 */
export type ContractList<T extends string = string> = Partial<Record<T, unknown>>

/**
 * IssuanceAllocator system contract names
 *
 * This includes all contracts that are part of the IssuanceAllocator deployment:
 * - IssuanceAllocator: Main contract (proxy)
 * - ProxyAdmin: Manages proxy upgrades
 * - TransparentUpgradeableProxy: The actual proxy contract
 */
export const IssuanceContractNameList = [
  'IssuanceAllocator',
  'IssuanceAllocatorImplementation',
  'GraphProxyAdmin2',
  'TransparentUpgradeableProxy',
] as const

export type IssuanceContractName = (typeof IssuanceContractNameList)[number]

/**
 * Artifact paths for issuance contracts
 * Points to the compiled contract artifacts
 */
export const ISSUANCE_ARTIFACTS_PATH = path.resolve(
  __dirname,
  '../../node_modules/@graphprotocol/contracts/artifacts/contracts',
)
export const OPENZEPPELIN_ARTIFACTS_PATH = path.resolve(
  __dirname,
  '../../node_modules/@openzeppelin/contracts/build/contracts',
)

/**
 * Mapping of contract names to their artifact paths
 */
export const IssuanceArtifactsMap: Record<IssuanceContractName, string> = {
  IssuanceAllocator: ISSUANCE_ARTIFACTS_PATH,
  IssuanceAllocatorImplementation: ISSUANCE_ARTIFACTS_PATH,
  GraphProxyAdmin2: OPENZEPPELIN_ARTIFACTS_PATH,
  TransparentUpgradeableProxy: OPENZEPPELIN_ARTIFACTS_PATH,
}

/**
 * Contract type definitions
 *
 * These extend the base Contract interface to provide type safety
 * while maintaining compatibility with ethers.js Contract instances
 */

/**
 * IssuanceAllocator contract interface (proxy)
 * This is the main contract that users interact with
 */
export interface IssuanceAllocator extends Contract {
  // Add specific method signatures here if needed for type safety
  // For now, extending Contract provides basic functionality
}

/**
 * IssuanceAllocator implementation contract interface
 * This is the actual contract logic behind the proxy
 */
export interface IssuanceAllocatorImpl extends Contract {
  // Implementation-specific methods if needed
}

/**
 * ProxyAdmin contract interface
 * Manages proxy upgrades and administration
 */
export interface ProxyAdmin extends Contract {
  // ProxyAdmin-specific methods if needed
}

/**
 * TransparentUpgradeableProxy contract interface
 * The proxy contract that delegates to implementations
 */
export interface TransparentUpgradeableProxy extends Contract {
  // Proxy-specific methods if needed
}

/**
 * Complete IssuanceAllocator contract collection interface
 *
 * This interface ensures type safety when loading all contracts
 * and provides IntelliSense support for contract access
 */
export interface IssuanceContracts extends ContractList<IssuanceContractName> {
  /** Main IssuanceAllocator contract (proxy) - primary interface for users */
  IssuanceAllocator: IssuanceAllocator

  /** IssuanceAllocator implementation contract - contains the actual logic */
  IssuanceAllocatorImplementation: IssuanceAllocatorImpl

  /** GraphProxyAdmin2 contract - manages proxy upgrades (governance-controlled) */
  GraphProxyAdmin2: ProxyAdmin

  /** TransparentUpgradeableProxy contract - the proxy itself */
  TransparentUpgradeableProxy: TransparentUpgradeableProxy
}

/**
 * Type guard to check if a string is a valid IssuanceContractName
 *
 * @param name - String to check
 * @returns True if the name is a valid contract name
 */
export function isIssuanceContractName(name: unknown): name is IssuanceContractName {
  return typeof name === 'string' && IssuanceContractNameList.includes(name as IssuanceContractName)
}

/**
 * Get the artifact path for a given contract name
 *
 * @param contractName - Name of the contract
 * @returns Path to the contract's artifacts
 */
export function getArtifactPath(contractName: IssuanceContractName): string {
  return IssuanceArtifactsMap[contractName]
}
