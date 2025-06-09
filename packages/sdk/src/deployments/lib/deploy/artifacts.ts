import { artifactsDir } from '@graphprotocol/contracts'
import * as fs from 'fs'
import { Artifacts } from 'hardhat/internal/artifacts'
import type { Artifact } from 'hardhat/types'
import * as path from 'path'

// Cache for contract path mappings to avoid repeated directory walking
const contractPathCache = new Map<string, Map<string, string>>()

/**
 * Load a contract's artifact from the build output folder
 * This function works like an API - it finds artifacts using module resolution,
 * not relative to the calling code's location.
 * @param name Name of the contract
 * @param buildDir Path to the build output folder(s). Optional override for module resolution.
 * @returns The artifact corresponding to the contract name
 */
export const loadArtifact = (name: string, buildDir?: string[] | string): Artifact => {
  let artifacts: Artifacts | undefined
  let artifact: Artifact | undefined

  // Use imported artifacts directory if no buildDir provided or empty
  if (!buildDir || (Array.isArray(buildDir) && buildDir.length === 0)) {
    buildDir = [artifactsDir]
  }

  if (typeof buildDir === 'string') {
    buildDir = [buildDir]
  }

  for (const dir of buildDir) {
    try {
      artifacts = new Artifacts(dir)

      // When using instrumented artifacts, try fully qualified name first to avoid conflicts
      if (buildDir.length > 0 && buildDir[0] !== artifactsDir && name.indexOf(':') === -1) {
        const localQualifiedName = getCachedContractPath(name, dir)
        if (localQualifiedName) {
          try {
            artifact = artifacts.readArtifactSync(localQualifiedName)
            break
          } catch {
            // Fall back to original name if fully qualified doesn't work
          }
        }
      }

      artifact = artifacts.readArtifactSync(name)
      break
    } catch (error) {
      const message = error instanceof Error ? error.message : error
      console.error(`Could not load artifact ${name} from ${dir} - ${message}`)
    }
  }

  if (artifact === undefined) {
    throw new Error(`Could not load artifact ${name}`)
  }

  return artifact
}

/**
 * Get the fully qualified contract path using a cached lookup.
 * Builds and caches the contract path mapping once per artifacts directory for performance.
 * @param contractName Name of the contract to find
 * @param artifactsDir Path to the artifacts directory
 * @returns Fully qualified contract path or null if not found
 */
function getCachedContractPath(contractName: string, artifactsDir: string): string | null {
  // Check if we have a cache for this artifacts directory
  let dirCache = contractPathCache.get(artifactsDir)

  if (!dirCache) {
    // Build cache for this directory
    dirCache = buildContractPathCache(artifactsDir)
    contractPathCache.set(artifactsDir, dirCache)
  }

  return dirCache.get(contractName) || null
}

/**
 * Build a complete cache of all contract paths in an artifacts directory.
 * Walks the directory tree once and maps contract names to their fully qualified paths.
 * @param artifactsDir Path to the artifacts directory
 * @returns Map of contract names to fully qualified paths
 */
function buildContractPathCache(artifactsDir: string): Map<string, string> {
  const cache = new Map<string, string>()

  try {
    const contractsDir = path.join(artifactsDir, 'contracts')
    if (!fs.existsSync(contractsDir)) {
      return cache
    }

    // Walk the entire directory tree once and cache all contracts
    walkDirectoryAndCache(contractsDir, contractsDir, cache)
  } catch {
    // Return empty cache on error
  }

  return cache
}

// Recursively walk directory and cache all contract paths
function walkDirectoryAndCache(dir: string, contractsDir: string, cache: Map<string, string>): void {
  try {
    const entries = fs.readdirSync(dir, { withFileTypes: true })

    for (const entry of entries) {
      const fullPath = path.join(dir, entry.name)

      if (entry.isDirectory()) {
        // Check if this is a .sol directory that might contain contracts
        if (entry.name.endsWith('.sol')) {
          // Look for all .json files in this directory (excluding .dbg.json)
          try {
            const contractFiles = fs.readdirSync(fullPath, { withFileTypes: true })
            for (const contractFile of contractFiles) {
              if (
                contractFile.isFile() &&
                contractFile.name.endsWith('.json') &&
                !contractFile.name.endsWith('.dbg.json')
              ) {
                const contractName = contractFile.name.replace('.json', '')
                const relativePath = path.relative(contractsDir, fullPath)
                const qualifiedName = `contracts/${relativePath.replace(/\.sol$/, '')}.sol:${contractName}`
                cache.set(contractName, qualifiedName)
              }
            }
          } catch {
            // Skip directories we can't read
          }
        }

        // Recursively search subdirectories
        walkDirectoryAndCache(fullPath, contractsDir, cache)
      }
    }
  } catch {
    // Skip directories we can't read
  }
}
