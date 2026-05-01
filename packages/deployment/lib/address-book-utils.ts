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
// Fork Auto-Detection
// ============================================================================

/**
 * Build a map from RPC URL hostname to network name using rocketh config.
 * Used by autoDetectForkNetwork() to match anvil's forkUrl.
 */
function buildRpcHostToNetworkMap(): Map<string, { name: string; chainId: number }> {
  const map = new Map<string, { name: string; chainId: number }>()
  const environments = rockethConfig.environments
  const chains = rockethConfig.chains
  if (!environments || !chains) return map

  for (const [envName, envConfig] of Object.entries(environments)) {
    const chainId = (envConfig as { chain: number }).chain
    const chainConfig = (chains as Record<number, unknown>)[chainId] as
      | { info?: { rpcUrls?: { default?: { http?: readonly string[] } } } }
      | undefined
    const rpcUrls = chainConfig?.info?.rpcUrls?.default?.http
    if (!rpcUrls) continue

    for (const rpcUrl of rpcUrls) {
      try {
        const hostname = new URL(rpcUrl).hostname
        map.set(hostname, { name: envName, chainId })
      } catch {
        // Skip invalid URLs
      }
    }
  }
  return map
}

/**
 * Auto-detect the fork network by querying anvil's `anvil_nodeInfo` RPC method.
 *
 * If FORK_NETWORK is already set, this is a no-op.
 * If the provider is an anvil fork, extracts the fork URL and matches it
 * against known network RPC hostnames from rocketh config.
 *
 * On success, sets process.env.FORK_NETWORK so all downstream synchronous
 * functions (isForkMode, getForkNetwork, etc.) work without changes.
 *
 * @param rpcUrl - The RPC URL to query (default: http://127.0.0.1:8545)
 * @returns The detected network name, or null if not a fork / not detectable
 */
export async function autoDetectForkNetwork(rpcUrl = 'http://127.0.0.1:8545'): Promise<string | null> {
  // Already set — nothing to do
  if (process.env.FORK_NETWORK || process.env.HARDHAT_FORK) {
    return process.env.FORK_NETWORK || process.env.HARDHAT_FORK || null
  }

  try {
    const response = await fetch(rpcUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ jsonrpc: '2.0', method: 'anvil_nodeInfo', params: [], id: 1 }),
    })
    const json = (await response.json()) as {
      result?: { forkConfig?: { forkUrl?: string } }
    }
    const forkUrl = json.result?.forkConfig?.forkUrl
    if (!forkUrl) return null

    // Match fork URL hostname against known networks
    const hostMap = buildRpcHostToNetworkMap()
    const forkHostname = new URL(forkUrl).hostname
    const match = hostMap.get(forkHostname)
    if (!match) return null

    // Set env var so all synchronous fork detection works downstream
    process.env.FORK_NETWORK = match.name
    return match.name
  } catch {
    // Not reachable or not anvil — not a fork
    return null
  }
}

// ============================================================================
// Fork Mode Detection
// ============================================================================

/** Network names that are local/test and support fork mode */
const LOCAL_NETWORKS = new Set(['localhost', 'fork', 'hardhat'])

/**
 * Check if the current network is a local network.
 * Uses explicit networkName if provided, falls back to HARDHAT_NETWORK env var.
 * Returns true if network is unknown (preserves existing behavior for callers
 * that don't pass context).
 */
function isLocalNetwork(networkName?: string): boolean {
  const name = networkName ?? process.env.HARDHAT_NETWORK
  if (name === undefined) return true
  return LOCAL_NETWORKS.has(name)
}

/**
 * Check if running in fork mode.
 *
 * Fork mode requires both:
 * 1. FORK_NETWORK or HARDHAT_FORK env var is set
 * 2. The current network is local (localhost, fork, hardhat)
 *
 * This prevents fork mode from activating when running against real networks
 * even if FORK_NETWORK is still set in the environment.
 *
 * @param networkName - Optional network name for explicit check (e.g., env.name).
 *                      Falls back to HARDHAT_NETWORK env var if not provided.
 */
export function isForkMode(networkName?: string): boolean {
  if (!isLocalNetwork(networkName)) return false
  return !!(process.env.HARDHAT_FORK || process.env.FORK_NETWORK)
}

/**
 * Get the fork network name from environment.
 * Returns null if not in fork mode or if running on a real network.
 *
 * @param networkName - Optional network name for explicit check.
 *                      Falls back to HARDHAT_NETWORK env var if not provided.
 */
export function getForkNetwork(networkName?: string): string | null {
  if (!isLocalNetwork(networkName)) return null
  return process.env.HARDHAT_FORK || process.env.FORK_NETWORK || null
}

// ============================================================================
// Local Network Detection
// ============================================================================

/**
 * Check if running against the Graph local network (rem-local-network).
 *
 * The local network uses chainId 1337 and deploys contracts from scratch.
 * Address books use addresses-local-network.json files which are symlinked
 * to mounted config files in the Docker container (populated by Phase 1).
 */
export function isLocalNetworkMode(): boolean {
  return process.env.HARDHAT_NETWORK === 'localNetwork'
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
export function getForkTargetChainId(networkName?: string): number | null {
  const forkNetwork = getForkNetwork(networkName)
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
  const forkChainId = getForkTargetChainId(env.name)
  if (forkChainId !== null) {
    return forkChainId
  }

  // Not in fork mode - get actual chain ID from provider
  const chainIdHex = await env.network.provider.request({ method: 'eth_chainId' })
  const providerChainId = Number(chainIdHex)

  // If we're on local chain 31337 without FORK_NETWORK set, the user is most
  // likely running against an anvil fork. Try auto-detecting once so callers
  // (per-component sync, status scripts) can resolve the right address book
  // without requiring the global sync script to have run first.
  if (providerChainId === 31337 && !getForkNetwork(env.name)) {
    const detected = await autoDetectForkNetwork()
    if (detected) {
      const detectedForkChainId = getForkTargetChainId(env.name)
      if (detectedForkChainId !== null) return detectedForkChainId
    }
  }

  return providerChainId
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
 * In local network mode, returns path to addresses-local-network.json.
 * In normal mode, returns path to package address book.
 */
export function getHorizonAddressBookPath(): string {
  if (isForkMode()) {
    const { horizonPath } = ensureForkAddressBooks()
    return horizonPath
  }
  if (isLocalNetworkMode()) {
    return require.resolve('@graphprotocol/horizon/addresses-local-network.json')
  }
  return require.resolve('@graphprotocol/horizon/addresses.json')
}

/**
 * Get the path to the SubgraphService address book.
 * In fork mode, returns path to fork-local copy.
 * In local network mode, returns path to addresses-local-network.json.
 * In normal mode, returns path to package address book.
 */
export function getSubgraphServiceAddressBookPath(): string {
  if (isForkMode()) {
    const { subgraphServicePath } = ensureForkAddressBooks()
    return subgraphServicePath
  }
  if (isLocalNetworkMode()) {
    return require.resolve('@graphprotocol/subgraph-service/addresses-local-network.json')
  }
  return require.resolve('@graphprotocol/subgraph-service/addresses.json')
}

/**
 * Get the path to the Issuance address book.
 * In fork mode, returns path to fork-local copy.
 * In local network mode, returns path to addresses-local-network.json.
 * In normal mode, returns path to package address book.
 */
export function getIssuanceAddressBookPath(): string {
  if (isForkMode()) {
    const { issuancePath } = ensureForkAddressBooks()
    return issuancePath
  }
  if (isLocalNetworkMode()) {
    return require.resolve('@graphprotocol/issuance/addresses-local-network.json')
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
