/**
 * Formatting helpers for human-readable display of on-chain values.
 */

import { formatEther } from 'viem'

/** Format a wei amount as GRT (e.g. `6036500000000000000n` → `"6.0365 GRT"`). */
export function formatGRT(wei: bigint): string {
  return `${formatEther(wei)} GRT`
}
