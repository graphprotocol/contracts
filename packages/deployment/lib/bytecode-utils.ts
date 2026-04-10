import { keccak256, toUtf8Bytes } from 'ethers'

/**
 * Bytecode utilities for smart contract deployment.
 *
 * These utilities handle bytecode hashing for change detection:
 * - Strip Solidity CBOR metadata (varies between compilations)
 * - Resolve library placeholders using actual library bytecode
 * - Compute stable bytecode hash for comparison
 *
 * This allows detecting when local artifact code has changed by comparing
 * stored bytecodeHash with the current artifact's hash.
 */

/**
 * Hardhat artifact link references: sourcePath → libraryName → offsets[]
 */
export type LinkReferences = Record<string, Record<string, Array<{ length: number; start: number }>>>

/**
 * Resolves a library artifact given its source path and name.
 * Returns the artifact's deployedBytecode and its own linkReferences (for recursion).
 */
export type LibraryArtifactResolver = (
  sourcePath: string,
  libraryName: string,
) => { deployedBytecode: string; deployedLinkReferences?: LinkReferences } | undefined

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
 * Compute the Solidity library placeholder hash for a given source path and name.
 * This is keccak256("sourcePath:libraryName") truncated to 34 hex chars (17 bytes).
 */
function libraryPlaceholderHash(sourcePath: string, libraryName: string): string {
  return keccak256(toUtf8Bytes(`${sourcePath}:${libraryName}`)).slice(2, 36)
}

/**
 * Resolve library placeholders in bytecode using actual library bytecode hashes.
 *
 * For each library in deployedLinkReferences, computes its bytecode hash
 * (recursively resolving its own library deps) and substitutes that hash
 * (truncated to 20 bytes / 40 hex chars) into the placeholder slots.
 *
 * This means the final hash reflects both the contract's code and all
 * transitive library code. If any library changes, the hash changes.
 */
function resolveLibraryPlaceholders(
  bytecode: string,
  linkReferences: LinkReferences | undefined,
  resolver: LibraryArtifactResolver | undefined,
): string {
  if (!linkReferences || !resolver) {
    // No link references or no resolver — zero out any remaining placeholders
    return bytecode.replace(/__\$[0-9a-fA-F]{34}\$__/g, '0'.repeat(40))
  }

  let result = bytecode
  for (const [sourcePath, libraries] of Object.entries(linkReferences)) {
    for (const libraryName of Object.keys(libraries)) {
      const placeholderHash = libraryPlaceholderHash(sourcePath, libraryName)
      const placeholder = `__\\$${placeholderHash}\\$__`

      const libArtifact = resolver(sourcePath, libraryName)
      let replacement: string
      if (libArtifact) {
        // Recursively compute the library's bytecode hash (handles nested deps)
        const libHash = computeBytecodeHashWithLibraries(
          libArtifact.deployedBytecode,
          libArtifact.deployedLinkReferences,
          resolver,
        )
        // Use first 40 hex chars (20 bytes) of the hash as the replacement
        replacement = libHash.slice(2, 42)
      } else {
        // Library artifact not available — zero fill
        replacement = '0'.repeat(40)
      }

      result = result.replace(new RegExp(placeholder, 'g'), replacement)
    }
  }

  // Zero any remaining unresolved placeholders (shouldn't happen but defensive)
  return result.replace(/__\$[0-9a-fA-F]{34}\$__/g, '0'.repeat(40))
}

/**
 * Compute a stable hash of bytecode for change detection, with library resolution.
 *
 * Normalizations applied before hashing:
 * - Strip CBOR metadata suffix (varies between compilations)
 * - Resolve library placeholders with actual library bytecode hashes
 *
 * @param bytecode - The bytecode to hash
 * @param linkReferences - Artifact's deployedLinkReferences (optional)
 * @param resolver - Function to load library artifacts (optional)
 * @returns keccak256 hash of the normalized bytecode
 */
function computeBytecodeHashWithLibraries(
  bytecode: string,
  linkReferences: LinkReferences | undefined,
  resolver: LibraryArtifactResolver | undefined,
): string {
  const stripped = stripMetadata(bytecode)
  const resolved = resolveLibraryPlaceholders(stripped, linkReferences, resolver)
  const prefixed = resolved.startsWith('0x') ? resolved : `0x${resolved}`
  return keccak256(prefixed)
}

/**
 * Compute a stable hash of bytecode for change detection.
 *
 * For simple contracts (no library references), pass just the bytecode.
 * For contracts with external libraries, pass linkReferences and a resolver
 * to include transitive library code in the hash.
 *
 * @param bytecode - The bytecode to hash (typically artifact.deployedBytecode)
 * @param linkReferences - Artifact's deployedLinkReferences (optional)
 * @param resolver - Function to load library artifacts for recursive resolution (optional)
 * @returns keccak256 hash of the bytecode with metadata stripped
 */
export function computeBytecodeHash(
  bytecode: string,
  linkReferences?: LinkReferences,
  resolver?: LibraryArtifactResolver,
): string {
  return computeBytecodeHashWithLibraries(bytecode, linkReferences, resolver)
}
