#!/usr/bin/env node
/**
 * Repository Comparison Script
 *
 * Compares contract artifacts between two repository directories to detect functional differences.
 * This is useful for verifying that dependency upgrades or other changes don't affect contract bytecode.
 *
 * Usage: ./scripts/compare-repo-contract-bytecode-excluding-metadata.mjs <repo1_path> <repo2_path>
 * Example: ./scripts/compare-repo-contract-bytecode-excluding-metadata.mjs /path/to/repo-v3.4.1 /path/to/repo-v3.4.2
 *
 * The script will:
 * 1. Auto-discover all artifact directories in both repositories
 * 2. Find matching contracts between the repositories
 * 3. Compare bytecode while stripping metadata hashes
 * 4. Report functional differences
 */

import { existsSync, readdirSync, readFileSync, statSync } from 'fs'
import { basename, join, relative, resolve } from 'path'

/**
 * Strip Solidity metadata hash from bytecode to focus on functional differences.
 *
 * Solidity appends CBOR-encoded metadata at the end of contract bytecode:
 * - a264697066735822 = CBOR encoding of {"ipfs": bytes(
 * - [68 hex chars] = 34-byte IPFS multihash (0x1220 prefix + 32-byte SHA2-256 hash)
 * - 64736f6c63 = CBOR encoding of "solc"
 * - [variable] = CBOR-encoded version bytes (e.g., 0x430007060033 for v0.7.6)
 *
 * Example: a264697066735822<1220+hash>64736f6c63430007060033
 *          └─ ipfs ──┘ └─34 bytes─┘ └solc┘ └─ version ─┘
 */
function stripMetadata(bytecode) {
  if (bytecode.startsWith('0x')) {
    bytecode = bytecode.slice(2)
  }

  // Match and remove the complete CBOR metadata suffix
  // Note: 68 hex chars = 34 bytes (multihash prefix 0x1220 + 32-byte hash)
  return bytecode.replace(/a264697066735822[a-fA-F0-9]{68}64736f6c63[a-fA-F0-9]+$/, '')
}

/**
 * Extract and process bytecode from contract artifact JSON file.
 */
function getContractBytecode(artifactFile) {
  try {
    const artifact = JSON.parse(readFileSync(artifactFile, 'utf-8'))

    const bytecode = artifact.bytecode || ''
    if (!bytecode || bytecode === '0x') {
      return null
    }

    return stripMetadata(bytecode)
  } catch {
    return null
  }
}

/**
 * Recursively find all files matching a pattern.
 */
function findFiles(dir, pattern, results = []) {
  if (!existsSync(dir)) {
    return results
  }

  try {
    const entries = readdirSync(dir)

    for (const entry of entries) {
      const fullPath = join(dir, entry)
      const stat = statSync(fullPath)

      if (stat.isDirectory()) {
        findFiles(fullPath, pattern, results)
      } else if (pattern.test(entry)) {
        results.push(fullPath)
      }
    }
  } catch {
    // Ignore permission errors
  }

  return results
}

/**
 * Find all artifact directories in a repository.
 * Returns list of [packageName, artifactPath] tuples.
 */
function findArtifactDirectories(repoPath) {
  const artifactDirs = []

  // Standard artifact patterns
  const patterns = ['packages/*/artifacts', 'packages/*/build/artifacts', 'packages/*/build/contracts']

  for (const pattern of patterns) {
    const [packagesDir, _glob, ...rest] = pattern.split('/')
    const packagesPath = join(repoPath, packagesDir)

    if (!existsSync(packagesPath)) continue

    try {
      const packages = readdirSync(packagesPath)

      for (const pkg of packages) {
        const artifactPath = join(packagesPath, pkg, ...rest)
        if (existsSync(artifactPath) && statSync(artifactPath).isDirectory()) {
          artifactDirs.push([pkg, artifactPath])
        }
      }
    } catch {
      // Ignore errors
    }
  }

  return artifactDirs
}

/**
 * Find all contract artifact JSON files in an artifact directory.
 * Returns object mapping relativePath -> absolutePath.
 */
function findContractArtifacts(artifactDir) {
  const contracts = {}
  const jsonFiles = findFiles(artifactDir, /\.json$/)

  for (const jsonFile of jsonFiles) {
    // Skip debug files
    if (jsonFile.endsWith('.dbg.json')) {
      continue
    }

    // Skip interface files (but not IL* files)
    const name = basename(jsonFile)
    if (name.startsWith('I') && !name.startsWith('IL')) {
      continue
    }

    // Get relative path from artifact directory
    const relPath = relative(artifactDir, jsonFile)
    contracts[relPath] = jsonFile
  }

  return contracts
}

/**
 * Compare contract artifacts between two repositories.
 */
function compareRepositories(repo1Path, repo2Path) {
  console.log('🔍 Comparing repositories:')
  console.log(`   Repo 1: ${repo1Path}`)
  console.log(`   Repo 2: ${repo2Path}`)
  console.log('   Excluding metadata hashes to focus on functional differences\n')

  // Find artifact directories in both repos
  const repo1Artifacts = findArtifactDirectories(repo1Path)
  const repo2Artifacts = findArtifactDirectories(repo2Path)

  // Group by package name
  const repo1Packages = Object.fromEntries(repo1Artifacts)
  const repo2Packages = Object.fromEntries(repo2Artifacts)

  // Find common packages
  const commonPackages = Object.keys(repo1Packages).filter((pkg) => pkg in repo2Packages)

  if (commonPackages.length === 0) {
    console.log('❌ No common packages found between repositories!')
    return
  }

  let totalCompared = 0
  let totalIdentical = 0
  let totalDifferent = 0
  let totalNoBytecode = 0

  const identicalContracts = []
  const differentContracts = []

  for (const pkg of commonPackages.sort()) {
    console.log(`🔍 Comparing ${pkg}...`)
    console.log(`   Repo 1: ${repo1Packages[pkg]}`)
    console.log(`   Repo 2: ${repo2Packages[pkg]}`)

    // Find contracts in both packages
    const repo1Contracts = findContractArtifacts(repo1Packages[pkg])
    const repo2Contracts = findContractArtifacts(repo2Packages[pkg])

    // Find common contracts
    const commonContracts = Object.keys(repo1Contracts).filter((c) => c in repo2Contracts)

    if (commonContracts.length === 0) {
      console.log('   ❌ No common contracts found!\n')
      continue
    }

    console.log(`   📊 Found ${commonContracts.length} common contracts`)

    let packageIdentical = 0
    let packageDifferent = 0
    let packageNoBytecode = 0

    for (const contractPath of commonContracts.sort()) {
      // Get bytecode from both versions
      const bytecode1 = getContractBytecode(repo1Contracts[contractPath])
      const bytecode2 = getContractBytecode(repo2Contracts[contractPath])

      // Extract contract name for display
      const contractName = basename(contractPath, '.json')

      if (bytecode1 === null && bytecode2 === null) {
        console.log(`   ⚪ ${contractPath}`)
        packageNoBytecode++
        totalNoBytecode++
      } else if (bytecode1 === bytecode2) {
        console.log(`   ✅ ${contractPath}`)
        identicalContracts.push(`${pkg}/${contractPath} (${contractName})`)
        packageIdentical++
        totalIdentical++
      } else {
        console.log(`   🧨 ${contractPath}`)
        differentContracts.push(`${pkg}/${contractPath} (${contractName})`)
        packageDifferent++
        totalDifferent++
      }

      totalCompared++
    }

    console.log(
      `   📊 Package summary: ${packageIdentical} identical, ${packageDifferent} different, ${packageNoBytecode} no bytecode\n`,
    )
  }

  // Overall summary
  console.log('📋 OVERALL SUMMARY:\n')

  if (identicalContracts.length > 0) {
    console.log(`✅ FUNCTIONALLY IDENTICAL (${identicalContracts.length} contracts):`)
    for (const contract of identicalContracts) {
      console.log(`  - ${contract}`)
    }
    console.log()
  }

  if (differentContracts.length > 0) {
    console.log(`🧨 FUNCTIONAL DIFFERENCES (${differentContracts.length} contracts):`)
    for (const contract of differentContracts) {
      console.log(`  - ${contract}`)
    }
    console.log()
  } else {
    console.log('🧨 FUNCTIONAL DIFFERENCES (0 contracts):')
    console.log('  (none)\n')
  }

  console.log('📊 Final Summary:')
  console.log(`   Packages compared: ${commonPackages.length}`)
  console.log(`   Total contracts compared: ${totalCompared}`)
  console.log(`   No bytecode (interfaces/abstract): ${totalNoBytecode}`)
  console.log(`   Functionally identical: ${totalIdentical}`)
  console.log(`   Functional differences: ${totalDifferent}`)

  if (totalDifferent === 0) {
    console.log('\n🎉 SUCCESS: All contracts are functionally identical!')
    console.log('   Any differences were only in metadata hashes.')
  } else {
    console.log(`\n⚠️  WARNING: ${totalDifferent} contracts have functional differences!`)
    console.log('   Review the differences above before proceeding.')
  }
}

/**
 * Main entry point.
 */
function main() {
  if (process.argv.length !== 4) {
    console.log('Usage: ./scripts/compare-repo-contract-bytecode-excluding-metadata.mjs <repo1_path> <repo2_path>')
    console.log(
      'Example: ./scripts/compare-repo-contract-bytecode-excluding-metadata.mjs /path/to/repo-v3.4.1 /path/to/repo-v3.4.2',
    )
    process.exit(1)
  }

  const repo1Path = resolve(process.argv[2])
  const repo2Path = resolve(process.argv[3])

  if (!existsSync(repo1Path)) {
    console.log(`❌ Repository 1 does not exist: ${repo1Path}`)
    process.exit(1)
  }

  if (!existsSync(repo2Path)) {
    console.log(`❌ Repository 2 does not exist: ${repo2Path}`)
    process.exit(1)
  }

  if (repo1Path === repo2Path) {
    console.log(`❌ Both repository paths are the same: ${repo1Path}`)
    process.exit(1)
  }

  compareRepositories(repo1Path, repo2Path)
}

main()
