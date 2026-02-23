/**
 * Ethers helper for HH v2 (coverage version)
 * Provides compatibility layer for tests written for HH v3
 */

import * as networkHelpers from '@nomicfoundation/hardhat-network-helpers'
import { ethers } from 'hardhat'

export type HardhatEthers = typeof ethers

export type HardhatEthersSigner = Awaited<ReturnType<typeof ethers.getSigners>>[0]

/**
 * Get the ethers instance (HH v2 style - direct export)
 */
export async function getEthers(): Promise<HardhatEthers> {
  return ethers
}

/**
 * Get signers from the network
 */
export async function getSigners(): Promise<HardhatEthersSigner[]> {
  return ethers.getSigners()
}

/**
 * Get network helpers
 */
export async function getNetworkHelpers(): Promise<typeof networkHelpers> {
  return networkHelpers
}

/**
 * Reset cached ethers/signers (no-op in HH v2 - kept for API compatibility)
 */
export function resetEthersCache() {
  // No caching needed in HH v2
}
