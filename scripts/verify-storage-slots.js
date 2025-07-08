#!/usr/bin/env node

/**
 * This script verifies that the storage slot hashes in Solidity contracts
 * match the expected values calculated using the ERC-7201 namespaced storage pattern.
 *
 * Usage:
 * node scripts/verify-storage-slots.js [options] [path/to/contracts]
 *
 * Options:
 * --fix: Update incorrect hashes in the contracts
 * --verbose: Show more detailed output
 * path/to/contracts: Optional path to scan (defaults to checking all packages in the repo)
 */

const fs = require('fs')
const path = require('path')

// Import the shared storage location utilities
const { getNamespace, getNamespacedStorageLocation } = require('./utils/storage-locations')

// Constants
const REPO_ROOT = path.resolve(__dirname, '..')
const STORAGE_LOCATION_REGEX = /\/\/\/ @custom:storage-location erc7201:graphprotocol\.storage\.([a-zA-Z0-9_]+)/
const STORAGE_SLOT_REGEX = /\$\.slot := (0x[a-fA-F0-9]+)/

// Define standard package paths
const PACKAGE_PATHS = [
  path.resolve(REPO_ROOT, 'packages/issuance/contracts'),
  path.resolve(REPO_ROOT, 'packages/contracts/contracts'),
]

// Parse command line arguments
const args = process.argv.slice(2)
const shouldFix = args.includes('--fix')
const isVerbose = args.includes('--verbose')
const customPath = args.find((arg) => !arg.startsWith('--'))
const contractsPath = customPath ? path.resolve(process.cwd(), customPath) : null

// Track results
const results = {
  correct: [],
  incorrect: [],
  fixed: [],
  errors: [],
}

/**
 * Find all Solidity files in a directory recursively
 * @param {string} dir - Directory to search
 * @returns {string[]} - Array of file paths
 */
function findSolidityFiles(dir) {
  let results = []
  const files = fs.readdirSync(dir)

  for (const file of files) {
    const filePath = path.join(dir, file)
    const stat = fs.statSync(filePath)

    if (stat.isDirectory()) {
      results = results.concat(findSolidityFiles(filePath))
    } else if (file.endsWith('.sol')) {
      results.push(filePath)
    }
  }

  return results
}

/**
 * Extract contract information from a Solidity file
 * @param {string} filePath - Path to the Solidity file
 * @returns {Array<{contractName: string, currentHash: string, filePath: string, lineNumber: number}>} - Array of contract info objects
 */
function extractContractInfo(filePath) {
  const content = fs.readFileSync(filePath, 'utf8')
  const lines = content.split('\n')
  const contracts = []

  let currentContractName = null

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]

    // Look for storage location annotation
    const storageMatch = line.match(STORAGE_LOCATION_REGEX)
    if (storageMatch) {
      currentContractName = storageMatch[1]
      continue
    }

    // Look for storage slot hash
    if (currentContractName) {
      const slotMatch = line.match(STORAGE_SLOT_REGEX)
      if (slotMatch) {
        contracts.push({
          contractName: currentContractName,
          currentHash: slotMatch[1],
          filePath,
          lineNumber: i + 1,
        })
        currentContractName = null
      }
    }
  }

  return contracts
}

/**
 * Verify the storage slot hash for a contract
 * @param {Object} contract - Contract info object
 * @returns {Object} - Result object with verification status
 */
function verifyStorageSlot(contract) {
  const { contractName, currentHash } = contract
  const namespace = getNamespace(contractName)
  const expectedHash = getNamespacedStorageLocation(namespace)

  return {
    ...contract,
    namespace,
    expectedHash,
    isCorrect: currentHash.toLowerCase() === expectedHash.toLowerCase(),
  }
}

/**
 * Fix the storage slot hash in a file
 * @param {Object} contract - Contract info with verification result
 * @returns {boolean} - Whether the fix was successful
 */
function fixStorageSlot(contract) {
  const { filePath, currentHash, expectedHash } = contract

  try {
    const content = fs.readFileSync(filePath, 'utf8')
    const updatedContent = content.replace(currentHash, expectedHash)

    fs.writeFileSync(filePath, updatedContent, 'utf8')
    return true
  } catch (error) {
    console.error(`Error fixing ${filePath}:`, error)
    return false
  }
}

/**
 * Process a single directory
 * @param {string} dirPath - Path to the directory to process
 * @returns {Object} - Results for this directory
 */
function processDirectory(dirPath) {
  const dirResults = {
    correct: [],
    incorrect: [],
    fixed: [],
    errors: [],
  }

  try {
    // Find all Solidity files
    const files = findSolidityFiles(dirPath)
    if (isVerbose) {
      console.log(`Found ${files.length} Solidity files`)
    }

    // Extract and verify contract information
    for (const file of files) {
      try {
        const contracts = extractContractInfo(file)

        for (const contract of contracts) {
          const result = verifyStorageSlot(contract)

          if (result.isCorrect) {
            dirResults.correct.push(result)
          } else {
            dirResults.incorrect.push(result)

            if (shouldFix) {
              const fixed = fixStorageSlot(result)
              if (fixed) {
                dirResults.fixed.push(result)
              }
            }
          }
        }
      } catch (error) {
        if (isVerbose) {
          console.error(`Error processing ${file}:`, error)
        }
        dirResults.errors.push({ file, error: error.message })
      }
    }

    return dirResults
  } catch (error) {
    if (isVerbose) {
      console.error(`Error processing directory ${dirPath}:`, error)
    }
    dirResults.errors.push({ file: dirPath, error: error.message })
    return dirResults
  }
}

/**
 * Print results
 * @param {Object} results - Results object
 * @param {boolean} verbose - Whether to print verbose output
 */
function printResults(results, verbose) {
  console.log('\n=== Storage Slot Verification Results ===\n')

  console.log(`✅ Correct hashes: ${results.correct.length}`)
  if (verbose || results.correct.length < 10) {
    for (const contract of results.correct) {
      console.log(`  - ${contract.contractName}: ${contract.currentHash}`)
    }
  } else if (results.correct.length > 0) {
    // Just show a few examples if there are many
    console.log(`  - ${results.correct[0].contractName}: ${results.correct[0].currentHash}`)
    if (results.correct.length > 1) {
      console.log(`  - ${results.correct[1].contractName}: ${results.correct[1].currentHash}`)
    }
    console.log(`  - ... and ${results.correct.length - 2} more`)
  }

  console.log(`\n❌ Incorrect hashes: ${results.incorrect.length}`)
  for (const contract of results.incorrect) {
    console.log(`  - ${contract.contractName}:`)
    console.log(`    Current:  ${contract.currentHash}`)
    console.log(`    Expected: ${contract.expectedHash}`)
    console.log(`    File: ${contract.filePath}:${contract.lineNumber}`)
  }

  if (shouldFix) {
    console.log(`\n🔧 Fixed hashes: ${results.fixed.length}`)
    for (const contract of results.fixed) {
      console.log(`  - ${contract.contractName}: ${contract.currentHash} -> ${contract.expectedHash}`)
    }
  }

  if (results.errors.length > 0) {
    console.log(`\n⚠️ Errors: ${results.errors.length}`)
    for (const error of results.errors) {
      console.log(`  - ${error.file}: ${error.error}`)
    }
  }
}

/**
 * Main function
 */
function main() {
  try {
    if (contractsPath) {
      // Check a specific directory
      console.log(`Scanning for Solidity contracts in: ${contractsPath}`)

      if (!fs.existsSync(contractsPath)) {
        console.error(`Error: Directory not found: ${contractsPath}`)
        process.exit(1)
      }

      const dirResults = processDirectory(contractsPath)

      // Merge results
      results.correct = results.correct.concat(dirResults.correct)
      results.incorrect = results.incorrect.concat(dirResults.incorrect)
      results.fixed = results.fixed.concat(dirResults.fixed)
      results.errors = results.errors.concat(dirResults.errors)
    } else {
      // Check all packages by default
      console.log('Checking all packages for storage slot hashes...')

      // Process each directory and combine results
      for (const dirPath of PACKAGE_PATHS) {
        if (fs.existsSync(dirPath)) {
          console.log(`\nScanning for Solidity contracts in: ${dirPath}`)
          const dirResults = processDirectory(dirPath)

          // Merge results
          results.correct = results.correct.concat(dirResults.correct)
          results.incorrect = results.incorrect.concat(dirResults.incorrect)
          results.fixed = results.fixed.concat(dirResults.fixed)
          results.errors = results.errors.concat(dirResults.errors)
        } else if (isVerbose) {
          console.log(`Directory not found: ${dirPath}`)
        }
      }
    }

    // Print results
    printResults(results, isVerbose)

    // Exit with appropriate code
    if (results.incorrect.length > 0 && !shouldFix) {
      console.log('\n❌ Some storage slot hashes are incorrect. Run with --fix to update them.')
      process.exit(1)
    } else if (results.errors.length > 0) {
      console.log('\n⚠️ Completed with errors.')
      process.exit(1)
    } else {
      console.log('\n✅ All storage slot hashes are correct.')
      process.exit(0)
    }
  } catch (error) {
    console.error('Error:', error)
    process.exit(1)
  }
}

main()
