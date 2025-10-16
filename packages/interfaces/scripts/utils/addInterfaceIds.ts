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

    if (functions.length === 0) return '0x00000000'

    // XOR all function selectors together (ERC-165 standard)
    let interfaceId = BigInt(0)
    for (const func of functions) {
      // Build full function signature: name(type1,type2,...)
      const inputs = func.inputs?.map((input) => input.type).join(',') ?? ''
      const signature = `${func.name}(${inputs})`

      // Calculate selector (first 4 bytes of keccak256)
      const hash = ethers.id(signature)
      const selector = hash.slice(0, 10) // '0x' + 8 hex chars

      interfaceId ^= BigInt(selector)
    }

    return '0x' + interfaceId.toString(16).padStart(8, '0')
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
    let content = fs.readFileSync(factoryPath, 'utf-8')

    // Check if already has interface metadata
    if (content.includes('static readonly interfaceId') && content.includes('static readonly interfaceName')) {
      return false
    }

    // Extract ABI from the file
    const abiMatch = content.match(/const _abi = (\[[\s\S]*?\]) as const;/)
    if (!abiMatch) {
      return false
    }

    // Parse ABI - handle TypeScript syntax (trailing commas, unquoted keys, etc.)
    const abiString = abiMatch[1]
      .replace(/,(\s*[\]}])/g, '$1') // Remove trailing commas
      .replace(/([{,]\s*)([a-zA-Z_][a-zA-Z0-9_]*)(\s*:)/g, '$1"$2"$3') // Quote keys

    const abi = JSON.parse(abiString)

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
    content = content.replace(/(static readonly abi = _abi;)\n/, `$1\n${interfaceMetadata}`)

    // Write back to file
    fs.writeFileSync(factoryPath, content)

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
