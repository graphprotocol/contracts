/**
 * Fork testing utilities for TAP Escrow Recovery & Legacy Allocation Closure operations
 *
 * These utilities enable testing operations against a forked Arbitrum One chain
 * with impersonated accounts.
 */

import type { HardhatRuntimeEnvironment } from 'hardhat/types'
import type { Signer } from 'ethers'

// ============================================
// Network Detection
// ============================================

const LOCAL_NETWORKS = ['localhost', 'hardhat', 'localNetwork']

/**
 * Check if the current network is a local/forked network
 */
export function isLocalNetwork(hre: HardhatRuntimeEnvironment): boolean {
  return LOCAL_NETWORKS.includes(hre.network.name)
}

/**
 * Require that we're on a local network, throw otherwise
 */
export function requireLocalNetwork(hre: HardhatRuntimeEnvironment): void {
  if (!isLocalNetwork(hre)) {
    throw new Error(`Network ${hre.network.name} is not a local network. This operation requires localhost, hardhat, or localNetwork.`)
  }
}

// ============================================
// Account Utilities
// ============================================

/**
 * Fund an account with ETH for gas (useful for impersonated accounts)
 */
export async function fundAccount(
  hre: HardhatRuntimeEnvironment,
  address: string,
  amount: string = '1.0',
): Promise<void> {
  const [funder] = await hre.ethers.getSigners()
  const tx = await funder.sendTransaction({
    to: address,
    value: hre.ethers.parseEther(amount),
  })
  await tx.wait()
}

/**
 * Get an impersonated signer and fund it with ETH
 */
export async function getImpersonatedSigner(
  hre: HardhatRuntimeEnvironment,
  address: string,
  fundAmount: string = '1.0',
): Promise<Signer> {
  // Get impersonated signer
  const signer = await hre.ethers.getImpersonatedSigner(address)

  // Fund the impersonated account with ETH for gas
  await fundAccount(hre, address, fundAmount)

  return signer
}

// ============================================
// Time Manipulation
// ============================================

/**
 * Advance blockchain time by a specified number of seconds
 */
export async function advanceTime(
  hre: HardhatRuntimeEnvironment,
  seconds: number,
): Promise<void> {
  requireLocalNetwork(hre)
  await hre.ethers.provider.send('evm_increaseTime', [seconds])
  await hre.ethers.provider.send('evm_mine', [])
}

/**
 * Advance blockchain time by a specified number of days
 */
export async function advanceTimeDays(
  hre: HardhatRuntimeEnvironment,
  days: number,
): Promise<void> {
  const seconds = days * 24 * 60 * 60
  await advanceTime(hre, seconds)
}

/**
 * Get the current block timestamp
 */
export async function getBlockTimestamp(
  hre: HardhatRuntimeEnvironment,
): Promise<number> {
  const block = await hre.ethers.provider.getBlock('latest')
  return block!.timestamp
}

// ============================================
// Constants
// ============================================

export const FORK_DEFAULTS = {
  // Default ETH amount to fund impersonated accounts
  FUND_AMOUNT: '1.0',

  // 30 days in seconds (TAP escrow thawing period)
  THAW_PERIOD_SECONDS: 30 * 24 * 60 * 60,
} as const
