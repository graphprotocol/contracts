/**
 * Shared Task Utilities
 *
 * Common functions used across Hardhat tasks. Consolidates helpers that were
 * previously duplicated across grant-role, revoke-role, reo-tasks, eth-tasks,
 * grt-tasks, and check-deployer.
 */

import { configVariable } from 'hardhat/config'

import { type AddressBookType, CONTRACT_REGISTRY } from './contract-registry.js'
import { graph } from '../rocketh/deploy.js'

/**
 * Convert network name to env var prefix: arbitrumSepolia → ARBITRUM_SEPOLIA
 */
export function networkToEnvPrefix(networkName: string): string {
  return networkName.replace(/([a-z])([A-Z])/g, '$1_$2').toUpperCase()
}

/**
 * Resolve a configuration variable using Hardhat's hook chain (keystore + env fallback)
 *
 * Tries the Hardhat keystore plugin first, then falls back to environment variables.
 * Returns undefined if the variable is not found in either location.
 *
 * @param hre - Hardhat Runtime Environment
 * @param name - Configuration variable name (e.g., 'ARBITRUM_SEPOLIA_DEPLOYER_KEY')
 * @returns The resolved value or undefined if not set
 */
export async function resolveConfigVar(hre: unknown, name: string): Promise<string | undefined> {
  try {
    const variable = configVariable(name)
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const hooks = (hre as any).hooks

    const value = await hooks.runHandlerChain(
      'configurationVariables',
      'fetchValue',
      [variable],
      async (_context: unknown, v: { name: string }) => {
        const envValue = process.env[v.name]
        if (typeof envValue !== 'string') {
          throw new Error(`Variable ${v.name} not found`)
        }
        return envValue
      },
    )
    return value
  } catch {
    return undefined
  }
}

/**
 * Get the deployer key name for a network, handling fork mode.
 *
 * In fork mode (network name is 'fork'), uses the HARDHAT_FORK env var to
 * determine the source network. Falls back to 'arbitrumSepolia'.
 *
 * @param networkName - Network name (e.g., 'fork', 'arbitrumSepolia')
 * @returns Key name (e.g., 'ARBITRUM_SEPOLIA_DEPLOYER_KEY')
 */
export function getDeployerKeyName(networkName: string): string {
  const effectiveNetwork = networkName === 'fork' ? (process.env.HARDHAT_FORK ?? 'arbitrumSepolia') : networkName
  return `${networkToEnvPrefix(effectiveNetwork)}_DEPLOYER_KEY`
}

/**
 * Resolve contract from registry by name
 *
 * Searches across all address books for a matching contract with roles defined.
 * Returns the address book type and role list if found.
 */
export function resolveContractFromRegistry(
  contractName: string,
): { addressBook: AddressBookType; roles: readonly string[] } | null {
  for (const [book, contracts] of Object.entries(CONTRACT_REGISTRY)) {
    const contract = contracts[contractName as keyof typeof contracts] as { roles?: readonly string[] } | undefined
    if (contract?.roles) {
      return { addressBook: book as AddressBookType, roles: contract.roles }
    }
  }
  return null
}

/**
 * Get contract address from address book
 */
export function getContractAddress(addressBook: AddressBookType, contractName: string, chainId: number): string | null {
  const book =
    addressBook === 'issuance'
      ? graph.getIssuanceAddressBook(chainId)
      : addressBook === 'horizon'
        ? graph.getHorizonAddressBook(chainId)
        : graph.getSubgraphServiceAddressBook(chainId)

  // Address book type is a union — cast to access entryExists/getEntry with a runtime name
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const anyBook = book as any
  if (!anyBook.entryExists(contractName)) {
    return null
  }

  return anyBook.getEntry(contractName)?.address ?? null
}

/**
 * Format duration in seconds to human-readable string (e.g., "2d 3h 15m")
 */
export function formatDuration(seconds: bigint): string {
  const days = seconds / 86400n
  const hours = (seconds % 86400n) / 3600n
  const mins = (seconds % 3600n) / 60n

  if (days > 0n) {
    return `${days}d ${hours}h ${mins}m`
  } else if (hours > 0n) {
    return `${hours}h ${mins}m`
  } else {
    return `${mins}m`
  }
}

/**
 * Format timestamp to human-readable string (ISO format without milliseconds)
 */
export function formatTimestamp(timestamp: bigint): string {
  if (timestamp === 0n) {
    return 'never'
  }

  const date = new Date(Number(timestamp) * 1000)
  return date
    .toISOString()
    .replace(/\.000Z$/, '')
    .replace(/Z$/, '')
    .replace('T', ' ')
}
