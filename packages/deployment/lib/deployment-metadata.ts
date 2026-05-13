import type { DeploymentMetadata } from '@graphprotocol/toolshed/deployments'

/**
 * Subset of rocketh's `Deployment` / `DeployContractResult` shape needed
 * to materialize a `DeploymentMetadata` entry. `receipt.blockNumber` may be
 * a hex string (`DeployResult`), a bigint (viem receipt) or a number.
 */
type DeploymentResult = {
  transaction?: { hash?: string }
  argsData?: string
  receipt?: { blockNumber?: `0x${string}` | bigint | number }
}

/**
 * Optional overrides for fields rocketh's result may not carry directly.
 * `blockNumber` overrides any value extracted from `result.receipt.blockNumber`.
 */
type MetadataOverrides = {
  blockNumber?: number
  timestamp?: string
}

/**
 * Coerce rocketh's `receipt.blockNumber` (hex string, bigint, or number) to a plain
 * number. Returns `undefined` for missing values. Use this everywhere instead of
 * inline `parseInt`/`Number` so the conversion stays consistent.
 */
export function toBlockNumber(raw: `0x${string}` | bigint | number | undefined): number | undefined {
  if (raw === undefined) return undefined
  if (typeof raw === 'string') return Number(BigInt(raw))
  return Number(raw)
}

/**
 * Build a `DeploymentMetadata` entry from a rocketh deployment result.
 *
 * Returns `undefined` when the essential fields (txHash, argsData) are missing —
 * callers should skip recording rather than write a half-populated entry with
 * an empty sentinel txHash.
 *
 * @param result - Rocketh deployment / pending-impl result
 * @param bytecodeHash - Pre-computed bytecode hash (hashing inputs vary by caller)
 * @param overrides - Optional blockNumber / timestamp (e.g. fetched from a separate receipt query)
 */
export function buildDeploymentMetadata(
  result: DeploymentResult,
  bytecodeHash: string,
  overrides?: MetadataOverrides,
): DeploymentMetadata | undefined {
  if (!result.transaction?.hash || !result.argsData) return undefined
  const blockNumber = overrides?.blockNumber ?? toBlockNumber(result.receipt?.blockNumber)
  return {
    txHash: result.transaction.hash,
    argsData: result.argsData,
    bytecodeHash,
    ...(blockNumber !== undefined && { blockNumber }),
    ...(overrides?.timestamp && { timestamp: overrides.timestamp }),
  }
}
