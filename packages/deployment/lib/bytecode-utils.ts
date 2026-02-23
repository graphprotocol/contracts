import { keccak256 } from 'ethers'

/**
 * Bytecode utilities for smart contract deployment.
 *
 * These utilities handle bytecode hashing for change detection:
 * - Strip Solidity CBOR metadata (varies between compilations)
 * - Compute stable bytecode hash for comparison
 *
 * This allows detecting when local artifact code has changed by comparing
 * stored bytecodeHash with the current artifact's hash.
 */

/**
 * Strip Solidity metadata from bytecode.
 * Metadata is CBOR-encoded at the end, with last 2 bytes indicating length.
 */
export function stripMetadata(bytecode: string): string {
  if (!bytecode || bytecode.length < 4) return bytecode
  // Remove 0x prefix for processing
  const code = bytecode.startsWith('0x') ? bytecode.slice(2) : bytecode
  if (code.length < 4) return bytecode

  // Last 2 bytes = metadata length (big-endian)
  const metadataLength = parseInt(code.slice(-4), 16)
  // Sanity check: metadata should be reasonable size (< 500 bytes = 1000 hex chars)
  if (metadataLength > 500 || metadataLength * 2 + 4 > code.length) {
    return bytecode // Can't strip, return as-is
  }
  // Strip metadata + 2-byte length suffix
  const prefix = bytecode.startsWith('0x') ? '0x' : ''
  return prefix + code.slice(0, -(metadataLength * 2 + 4))
}

/**
 * Compute a stable hash of bytecode for change detection.
 *
 * Strips CBOR metadata suffix before hashing to ensure the hash is stable
 * across recompilations that don't change the actual contract logic.
 *
 * Use this to detect when local artifact bytecode has changed since deployment.
 *
 * @param bytecode - The bytecode to hash (typically artifact.deployedBytecode)
 * @returns keccak256 hash of the bytecode with metadata stripped
 */
export function computeBytecodeHash(bytecode: string): string {
  const stripped = stripMetadata(bytecode)
  // Ensure 0x prefix for keccak256
  const prefixed = stripped.startsWith('0x') ? stripped : `0x${stripped}`
  return keccak256(prefixed)
}
