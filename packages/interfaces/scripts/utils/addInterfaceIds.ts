#!/usr/bin/env node
/**
 * Post-process Typechain-generated factory files to add interface metadata
 *
 * This utility adds ERC-165 interface IDs and interface names to Typechain-generated
 * factory classes as static readonly properties.
 *
 * @example
 * ```typescript
 * import { addInterfaceIds } from './utils/addInterfaceIds'
 * addInterfaceIds('./types/factories')
 * ```
 */

import { ethers } from 'ethers'
import * as fs from 'fs'
import * as path from 'path'

// Constants for ERC-165 interface ID calculation
const EMPTY_INTERFACE_ID = '0x00000000'
const SELECTOR_LENGTH_WITH_PREFIX = 10 // '0x' + 8 hex characters
const INTERFACE_ID_LENGTH = 8 // 8 hex characters (4 bytes)

interface ProcessStats {
  processed: number
  skipped: number
  total: number
}

interface AbiItem {
  type: string
  name?: string
  inputs?: Array<{ type: string; name?: string }>
  [key: string]: unknown
}

/**
 * Calculate ERC-165 interface ID from contract ABI
 * @param abi - Contract ABI array
 * @returns Interface ID as hex string (e.g., "0x12345678")
 */
export function calculateInterfaceId(abi: AbiItem[]): string | null {
  try {
    // Filter to only functions (not events, errors, etc.)
    const functions = abi.filter((item) => item.type === 'function')

    if (functions.length === 0) return EMPTY_INTERFACE_ID

    // XOR all function selectors together (ERC-165 standard)
    let interfaceId = BigInt(0)
    for (const func of functions) {
      // Build full function signature: name(type1,type2,...)
      const inputs = func.inputs?.map((input) => input.type).join(',') ?? ''
      const signature = `${func.name}(${inputs})`

      // Calculate selector (first 4 bytes of keccak256)
      const hash = ethers.id(signature)
      const selector = hash.slice(0, SELECTOR_LENGTH_WITH_PREFIX)

      interfaceId ^= BigInt(selector)
    }

    return '0x' + interfaceId.toString(16).padStart(INTERFACE_ID_LENGTH, '0')
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    console.error(`Error calculating interface ID: ${message}`)
    return null
  }
}

/**
 * Add interface metadata to a single factory file
 * @param factoryPath - Absolute path to the factory file
 * @returns True if metadata was added, false if skipped
 */
export function addInterfaceIdToFactory(factoryPath: string): boolean {
  try {
    const content = fs.readFileSync(factoryPath, 'utf-8')

    // Check if already has interface metadata
    if (content.includes('static readonly interfaceId') && content.includes('static readonly interfaceName')) {
      return false
    }

    // Extract ABI from the file
    const abiMatch = content.match(/const _abi = (\[[\s\S]*?\]) as const;/)
    if (!abiMatch) {
      return false
    }

    // Parse ABI from Typechain-generated code
    // We use Function constructor here because:
    // 1. The source is Typechain-generated code (not user input)
    // 2. TypeScript syntax (trailing commas, unquoted keys) makes JSON.parse unsuitable
    // 3. A full AST parser would be overkill for this build-time utility
    // This is safe as it only runs during build on controlled, generated code.
    const abi = new Function(`return ${abiMatch[1]}`)() as AbiItem[]

    // Calculate interface ID
    const interfaceId = calculateInterfaceId(abi)
    if (!interfaceId) {
      return false
    }

    // Extract interface name from filename (e.g., "IPausableControl__factory.ts" -> "IPausableControl")
    const fileName = path.basename(factoryPath)
    const interfaceName = fileName.replace(/__factory\.ts$/, '')

    // Add interface metadata as static properties after the ABI
    const interfaceMetadata = `  // The following properties are automatically generated during the build process\n  static readonly interfaceId = "${interfaceId}" as const;\n  static readonly interfaceName = "${interfaceName}" as const;\n`

    // Insert after "static readonly abi"
    const replacementPattern = /(static readonly abi = _abi;)\n/
    const newContent = content.replace(replacementPattern, `$1\n${interfaceMetadata}`)

    // Validate that replacement succeeded
    if (newContent === content) {
      console.warn(
        `Warning: Failed to inject interface metadata into ${path.basename(factoryPath)} - pattern not found`,
      )
      return false
    }

    // Write back to file
    fs.writeFileSync(factoryPath, newContent)

    return true
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    console.error(`Error processing ${path.basename(factoryPath)}: ${message}`)
    return false
  }
}

/**
 * Recursively process all factory files in a directory
 * @param dir - Directory path to process
 * @returns Statistics about processing
 */
function processDirectory(dir: string): ProcessStats {
  const stats: ProcessStats = { processed: 0, skipped: 0, total: 0 }

  if (!fs.existsSync(dir)) {
    console.warn(`Directory does not exist: ${dir}`)
    return stats
  }

  const entries = fs.readdirSync(dir, { withFileTypes: true })

  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name)

    if (entry.isDirectory()) {
      const subStats = processDirectory(fullPath)
      stats.processed += subStats.processed
      stats.skipped += subStats.skipped
      stats.total += subStats.total
    } else if (entry.name.endsWith('__factory.ts')) {
      stats.total++
      const added = addInterfaceIdToFactory(fullPath)
      if (added) {
        stats.processed++
      } else {
        stats.skipped++
      }
    }
  }

  return stats
}

/**
 * Add interface IDs to all Typechain-generated factory files in a directory
 * @param factoriesDir - Path to the factories directory
 */
export function addInterfaceIds(factoriesDir: string): void {
  const stats = processDirectory(factoriesDir)

  if (stats.total === 0) {
    console.log('🔢 Factory files interface IDs: none found')
  } else if (stats.processed === 0) {
    console.log('🔢 Factory files interface IDs: up to date')
  } else {
    console.log(`🔢 Factory files interface IDs: generated for ${stats.processed} files`)
  }
}

// CLI entry point
if (require.main === module) {
  const factoriesDir = process.argv[2]
  if (!factoriesDir) {
    console.error('Usage: addInterfaceIds.ts <factories-dir>')
    process.exit(1)
  }
  addInterfaceIds(factoriesDir)
}
