/**
 * Address Book Utilities
 *
 * This module provides utilities for working with address books in deployment scripts.
 * It handles fork mode detection, chain ID resolution, and address book instantiation.
 *
 * Structure:
 * 1. Fork Mode Detection - Check if running in fork mode and get network info
 * 2. Chain ID Resolution - Get target chain IDs for address book lookups
 * 3. Fork State Management - Copy address books for fork-local modifications
 * 4. Address Book Factories - Create AddressBookOps instances for each package
 */

import { existsSync, mkdirSync, copyFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import path from 'node:path'

import type { Environment } from '@rocketh/core/types'
import type {
  GraphHorizonContractName,
  GraphIssuanceContractName,
  SubgraphServiceContractName,
} from '@graphprotocol/toolshed/deployments'
import {
  GraphHorizonAddressBook,
  GraphIssuanceAddressBook,
  SubgraphServiceAddressBook,
} from '@graphprotocol/toolshed/deployments'

import { config as rockethConfig } from '../rocketh/config.js'
import { AddressBookOps } from './address-book-ops.js'

const require = createRequire(import.meta.url)

// ============================================================================
// Fork Mode Detection
// ============================================================================

/**
 * Check if running in fork mode
 */
export function isForkMode(): boolean {
  return !!(process.env.HARDHAT_FORK || process.env.FORK_NETWORK)
}

/**
 * Get the fork network name from environment
 */
export function getForkNetwork(): string | null {
  return process.env.HARDHAT_FORK || process.env.FORK_NETWORK || null
}

/**
 * Get the fork state directory for a given network.
 * All fork-related state (address books, governance TXs) is stored here.
 *
 * Returns: fork/<envName>/<forkNetwork>/
 *
 * Stored outside deployments/ so rocketh manages its own directory cleanly.
 *
 * @param envName - Hardhat network name (e.g., 'fork', 'localhost')
 * @param forkNetwork - Fork network name (e.g., 'arbitrumSepolia', 'arbitrumOne')
 */
export function getForkStateDir(envName: string, forkNetwork: string): string {
  return path.resolve(process.cwd(), 'fork', envName, forkNetwork)
}

/**
 * Get the target chain ID for fork mode address book lookups.
 * Uses rocketh config to map FORK_NETWORK environment variable to actual chain IDs.
 *
 * Returns null if not in fork mode - callers should use provider chain ID instead.
 *
 * @example
 * const forkChainId = getForkTargetChainId()
 * const targetChainId = forkChainId ?? providerChainId
 */
export function getForkTargetChainId(): number | null {
  const forkNetwork = getForkNetwork()
  if (!forkNetwork) return null

  // Look up chain ID from rocketh config environments
  const environments = rockethConfig.environments
  if (!environments) {
    throw new Error('rocketh config missing environments')
  }

  const environment = environments[forkNetwork as keyof typeof environments]
  if (!environment) {
    throw new Error(`Unknown fork network: ${forkNetwork}. Not found in rocketh config.`)
  }

  const chainId = environment.chain
  if (typeof chainId !== 'number') {
    throw new Error(`Invalid chain ID for fork network ${forkNetwork}`)
  }

  return chainId
}

// ============================================================================
// Chain ID Resolution
// ============================================================================

/**
 * Get the target chain ID for address book and transaction operations.
 * This is the single canonical function for resolving chain IDs.
 *
 * In fork mode: Returns the fork target chain ID (e.g., 42161 for arbitrumOne fork)
 * In non-fork mode: Returns the provider's actual chain ID
 *
 * @param env - Rocketh environment (used to query provider)
 * @returns The target chain ID to use for address book lookups and transactions
 *
 * @example
 * const targetChainId = await getTargetChainIdFromEnv(env)
 * const addressBook = getIssuanceAddressBook(targetChainId)
 */
export async function getTargetChainIdFromEnv(env: Environment): Promise<number> {
  const forkChainId = getForkTargetChainId()
  if (forkChainId !== null) {
    return forkChainId
  }

  // Not in fork mode - get actual chain ID from provider
  const chainIdHex = await env.network.provider.request({ method: 'eth_chainId' })
  return Number(chainIdHex)
}

// ============================================================================
// Fork State Management
// ============================================================================

/**
 * Get the directory for fork-local address book copies.
 * Uses FORK_NETWORK to determine subdirectory.
 *
 * Note: This function doesn't have access to env.name, so it infers the hardhat
 * network from process.env.HARDHAT_NETWORK (set by Hardhat at runtime).
 * Falls back to 'localhost' if not set.
 */
function getForkAddressBooksDir(): string {
  const forkNetwork = getForkNetwork()
  if (!forkNetwork) {
    throw new Error('getForkAddressBooksDir called but not in fork mode')
  }
  // Infer hardhat network from environment (set by hardhat at runtime)
  const envName = process.env.HARDHAT_NETWORK || 'localhost'
  return getForkStateDir(envName, forkNetwork)
}

/**
 * Ensure fork address book copies exist.
 * Called once at the start of sync to set up fork-local copies.
 * Copies canonical address books to fork-state directory on first use.
 *
 * @returns Object with paths to the fork-local address books
 */
export function ensureForkAddressBooks(): {
  horizonPath: string
  subgraphServicePath: string
  issuancePath: string
} {
  const forkNetwork = getForkNetwork()
  if (!forkNetwork) {
    throw new Error('ensureForkAddressBooks called but not in fork mode')
  }

  const forkDir = getForkAddressBooksDir()

  // Create directory if it doesn't exist
  if (!existsSync(forkDir)) {
    mkdirSync(forkDir, { recursive: true })
  }

  const horizonSourcePath = require.resolve('@graphprotocol/horizon/addresses.json')
  const ssSourcePath = require.resolve('@graphprotocol/subgraph-service/addresses.json')
  const issuanceSourcePath = require.resolve('@graphprotocol/issuance/addresses.json')

  const horizonForkPath = path.join(forkDir, 'horizon-addresses.json')
  const ssForkPath = path.join(forkDir, 'subgraph-service-addresses.json')
  const issuanceForkPath = path.join(forkDir, 'issuance-addresses.json')

  // Copy if fork copies don't exist yet
  if (!existsSync(horizonForkPath)) {
    copyFileSync(horizonSourcePath, horizonForkPath)
  }
  if (!existsSync(ssForkPath)) {
    copyFileSync(ssSourcePath, ssForkPath)
  }
  if (!existsSync(issuanceForkPath)) {
    copyFileSync(issuanceSourcePath, issuanceForkPath)
  }

  return {
    horizonPath: horizonForkPath,
    subgraphServicePath: ssForkPath,
    issuancePath: issuanceForkPath,
  }
}

// ============================================================================
// Address Book Path Utilities
// ============================================================================

/**
 * Get the path to the Horizon address book.
 * In fork mode, returns path to fork-local copy.
 * In normal mode, returns path to package address book.
 */
export function getHorizonAddressBookPath(): string {
  if (isForkMode()) {
    const { horizonPath } = ensureForkAddressBooks()
    return horizonPath
  }
  return require.resolve('@graphprotocol/horizon/addresses.json')
}

/**
 * Get the path to the SubgraphService address book.
 * In fork mode, returns path to fork-local copy.
 * In normal mode, returns path to package address book.
 */
export function getSubgraphServiceAddressBookPath(): string {
  if (isForkMode()) {
    const { subgraphServicePath } = ensureForkAddressBooks()
    return subgraphServicePath
  }
  return require.resolve('@graphprotocol/subgraph-service/addresses.json')
}

/**
 * Get the path to the Issuance address book.
 * In fork mode, returns path to fork-local copy.
 * In normal mode, returns path to package address book.
 */
export function getIssuanceAddressBookPath(): string {
  if (isForkMode()) {
    const { issuancePath } = ensureForkAddressBooks()
    return issuancePath
  }
  return require.resolve('@graphprotocol/issuance/addresses.json')
}

// ============================================================================
// Address Book Factories
// ============================================================================

/**
 * Get an AddressBookOps instance for Graph Horizon contracts.
 * Automatically uses fork-local copy in fork mode.
 *
 * @param chainId - Target chain ID. In fork mode, uses fork target chain ID if not provided.
 *                  In non-fork mode, must be provided by caller (from provider).
 */
export function getHorizonAddressBook(chainId?: number): AddressBookOps<GraphHorizonContractName> {
  const targetChainId = chainId ?? getForkTargetChainId() ?? 31337
  const baseAddressBook = new GraphHorizonAddressBook(getHorizonAddressBookPath(), targetChainId)
  return new AddressBookOps(baseAddressBook)
}

/**
 * Get an AddressBookOps instance for Subgraph Service contracts.
 * Automatically uses fork-local copy in fork mode.
 *
 * @param chainId - Target chain ID. In fork mode, uses fork target chain ID if not provided.
 *                  In non-fork mode, must be provided by caller (from provider).
 */
export function getSubgraphServiceAddressBook(chainId?: number): AddressBookOps<SubgraphServiceContractName> {
  const targetChainId = chainId ?? getForkTargetChainId() ?? 31337
  const baseAddressBook = new SubgraphServiceAddressBook(getSubgraphServiceAddressBookPath(), targetChainId)
  return new AddressBookOps(baseAddressBook)
}

/**
 * Get an AddressBookOps instance for Graph Issuance contracts.
 * Automatically uses fork-local copy in fork mode.
 *
 * @param chainId - Target chain ID. In fork mode, uses fork target chain ID if not provided.
 *                  In non-fork mode, must be provided by caller (from provider).
 */
export function getIssuanceAddressBook(chainId?: number): AddressBookOps<GraphIssuanceContractName> {
  const targetChainId = chainId ?? getForkTargetChainId() ?? 31337
  const baseAddressBook = new GraphIssuanceAddressBook(getIssuanceAddressBookPath(), targetChainId)
  return new AddressBookOps(baseAddressBook)
}
