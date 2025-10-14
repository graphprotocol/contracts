#!/usr/bin/env node

const fs = require('fs')
const { execSync } = require('child_process')

/**
 * Extract solhint-disable rules from file content
 *
 * This function scans the file content and collects ALL file-level solhint-disable rules,
 * separating them into two categories:
 *
 * 1. **Pre-TODO disables**: Rules that appear before the TODO section (or at the top if no TODO).
 *    These are considered intentional long-term disables (e.g., "one-contract-per-file" for
 *    storage contracts) and should NOT be moved into the TODO section.
 *
 * 2. **TODO section disables**: Rules that appear within the TODO section (after the
 *    "TODO: Re-enable and fix issues" comment). These are temporary and should be
 *    consolidated/verified.
 *
 * The function returns ALL rules combined for verification purposes, but tracks which
 * category each set belongs to so the fix function can preserve pre-TODO disables.
 *
 * Example file structure:
 *   // solhint-disable one-contract-per-file          <- Pre-TODO (permanent)
 *   pragma solidity ^0.7.6;
 *   // TODO: Re-enable and fix issues when publishing a new version
 *   // solhint-disable gas-indexed-events             <- TODO section (temporary)
 *   // solhint-disable named-parameters-mapping       <- TODO section (temporary)
 *
 * @param {string} content - The file content to parse
 * @returns {{preTodoRules: string[], todoRules: string[], allRules: string[]}}
 *
 * Example return:
 * {
 *   preTodoRules: ["one-contract-per-file"],
 *   todoRules: ["gas-indexed-events", "named-parameters-mapping"],
 *   allRules: ["gas-indexed-events", "named-parameters-mapping", "one-contract-per-file"]
 * }
 *
 * Note: This does NOT collect from solhint-disable-next-line comments.
 */
function extractDisabledRulesFromContent(content) {
  const lines = content.split('\n')

  let todoLineIndex = -1
  let todoSectionEndIndex = -1
  const preTodoRules = []
  const todoRules = []

  // First pass: find TODO section boundaries
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].includes('TODO: Re-enable and fix issues')) {
      todoLineIndex = i
      // Find where TODO section ends (first non-comment line after TODO)
      for (let j = i + 1; j < lines.length; j++) {
        if (!lines[j].trim().startsWith('//')) {
          todoSectionEndIndex = j
          break
        }
      }
      break
    }
  }

  // Second pass: collect all file-level solhint-disable rules
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]

    if (!line.trim().startsWith('// solhint-disable ')) {
      continue
    }

    const rulesStr = line.replace('// solhint-disable ', '').trim().replace(/,$/, '')
    const rules = rulesStr
      .split(',')
      .map((r) => r.trim())
      .filter((r) => r)

    // Categorize based on location relative to TODO section
    if (todoLineIndex === -1 || i < todoLineIndex) {
      // No TODO section, or before TODO section
      preTodoRules.push(...rules)
    } else if (i > todoLineIndex && (todoSectionEndIndex === -1 || i < todoSectionEndIndex)) {
      // Within TODO section
      todoRules.push(...rules)
    } else {
      // After TODO section - also collect these for verification
      todoRules.push(...rules)
    }
  }

  const allRules = [...preTodoRules, ...todoRules].sort()

  return {
    preTodoRules: preTodoRules.sort(),
    todoRules: todoRules.sort(),
    allRules,
  }
}

/**
 * Extract solhint-disable rules from a file path
 * Wrapper around extractDisabledRulesFromContent that reads the file
 */
function extractDisabledRules(filePath) {
  const content = fs.readFileSync(filePath, 'utf8')
  return extractDisabledRulesFromContent(content)
}

/**
 * Get actual solhint issues for a file by removing ALL solhint-disable comments
 * This gives us the complete list of issues that need to be disabled
 */
function getActualIssues(filePath) {
  const path = require('path')

  try {
    const content = fs.readFileSync(filePath, 'utf8')

    // Remove all solhint-disable lines to get the full list of actual issues
    const cleanedLines = []

    for (const line of content.split('\n')) {
      // Skip all solhint-disable comments (both pre-TODO and TODO section)
      if (line.trim().startsWith('// solhint-disable ') || line.includes('TODO: Re-enable and fix issues')) {
        continue
      }
      cleanedLines.push(line)
    }

    const cleanedContent = cleanedLines.join('\n')

    // Create temp file in same directory as original to maintain import resolution context
    const absolutePath = path.resolve(filePath)
    const tempFile = absolutePath.replace('.sol', '.temp.sol')
    const fileDir = path.dirname(absolutePath)

    // Find the package root (directory containing node_modules or package.json)
    let packageRoot = fileDir
    while (packageRoot !== path.dirname(packageRoot)) {
      if (
        fs.existsSync(path.join(packageRoot, 'package.json')) ||
        fs.existsSync(path.join(packageRoot, 'node_modules'))
      ) {
        break
      }
      packageRoot = path.dirname(packageRoot)
    }

    fs.writeFileSync(tempFile, cleanedContent)

    try {
      // Find the root .solhint.json config
      let configPath = null
      let searchDir = packageRoot
      while (searchDir !== path.dirname(searchDir)) {
        const configFile = path.join(searchDir, '.solhint.json')
        if (fs.existsSync(configFile)) {
          configPath = configFile
          break
        }
        searchDir = path.dirname(searchDir)
      }

      // Run solhint from the package root with the config to ensure consistent behavior
      const relativeTempFile = path.relative(packageRoot, tempFile)
      const configArg = configPath ? `--config "${configPath}"` : ''
      const result = execSync(`npx solhint ${configArg} "${relativeTempFile}" -f json`, {
        cwd: packageRoot,
        encoding: 'utf8',
        stdio: ['pipe', 'pipe', 'pipe'],
      })

      fs.unlinkSync(tempFile) // Clean up temp file

      const issues = JSON.parse(result)
      const ruleIds = [...new Set(issues.map((issue) => issue.ruleId).filter((id) => id && id.trim()))].sort()

      return ruleIds
    } catch (error) {
      // Clean up temp file if it exists
      if (fs.existsSync(tempFile)) {
        fs.unlinkSync(tempFile)
      }
      console.error(`Error processing ${filePath}:`, error.message)
      return []
    }
  } catch (error) {
    console.error(`Error reading ${filePath}:`, error.message)
    return []
  }
}

/**
 * Fix disabled rules in file content
 * Strategy: Remove unnecessary rules from anywhere, add new rules only to TODO section
 *
 * @param {string} content - Original file content
 * @param {string[]} actualIssues - Array of rules that should be disabled
 * @param {string[]} preTodoRules - Array of rules currently in pre-TODO disables
 * @returns {string} Fixed content
 */
function fixDisabledRulesInContent(content, actualIssues, preTodoRules) {
  const lines = content.split('\n')

  // Calculate which pre-TODO rules to keep (only the ones actually needed)
  const neededPreTodoRules = preTodoRules.filter((rule) => actualIssues.includes(rule)).sort()

  // Calculate which rules need to go in TODO section (needed but not in pre-TODO)
  const neededTodoRules = actualIssues.filter((rule) => !neededPreTodoRules.includes(rule)).sort()

  const newLines = []
  let inTodoSection = false
  let todoSectionEnded = false
  let pragmaEndIndex = -1
  let foundPreTodoDisables = false

  // Process file line by line
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    const isDisableLine = line.trim().startsWith('// solhint-disable ')

    // Track pragma location
    if (line.trim().startsWith('pragma ')) {
      pragmaEndIndex = i
    }

    // Handle TODO section
    if (line.includes('TODO: Re-enable and fix issues')) {
      inTodoSection = true
      continue // Skip TODO comment
    }

    if (inTodoSection && isDisableLine) {
      continue // Skip old TODO section disables
    }

    if (inTodoSection && !line.trim().startsWith('//')) {
      todoSectionEnded = true
    }

    if (inTodoSection && todoSectionEnded && line.trim() !== '') {
      inTodoSection = false
    }

    // Handle pre-TODO disables (any disable not in TODO section): replace with cleaned version
    if (!inTodoSection && isDisableLine) {
      if (!foundPreTodoDisables && neededPreTodoRules.length > 0) {
        // Add cleaned pre-TODO disable before pragma if we haven't added it yet
        if (pragmaEndIndex === -1) {
          // Haven't seen pragma yet, add it here
          newLines.push(`// solhint-disable ${neededPreTodoRules.join(', ')}`)
          foundPreTodoDisables = true
        }
        // If pragma already passed, we'll add it later
      }
      // Skip all original pre-TODO disable lines
      // If we're removing ALL pre-TODO disables (neededPreTodoRules is empty), also skip the blank line that follows
      if (neededPreTodoRules.length === 0 && i + 1 < lines.length && lines[i + 1].trim() === '') {
        i++ // Skip the next blank line too
      }
      continue
    }

    // Keep all other lines
    if (!inTodoSection) {
      newLines.push(line)
    }
  }

  // Add pre-TODO disables if we didn't find any existing ones but need them
  if (!foundPreTodoDisables && neededPreTodoRules.length > 0) {
    // Insert before first pragma or at the beginning
    const insertIdx = pragmaEndIndex >= 0 ? newLines.findIndex((l) => l.trim().startsWith('pragma ')) : 1
    if (insertIdx >= 0) {
      newLines.splice(insertIdx, 0, `// solhint-disable ${neededPreTodoRules.join(', ')}`, '')
    }
  }

  // Add TODO section if needed
  if (neededTodoRules.length > 0) {
    let insertIndex = newLines.findIndex((l) => l.trim().startsWith('pragma '))
    if (insertIndex >= 0) {
      insertIndex++ // After pragma

      // Skip existing blank lines
      while (insertIndex < newLines.length && newLines[insertIndex].trim() === '') {
        insertIndex++
      }

      const todoSection = [
        '// TODO: Re-enable and fix issues when publishing a new version',
        `// solhint-disable ${neededTodoRules.join(', ')}`,
        '',
      ]

      newLines.splice(insertIndex, 0, ...todoSection)
    }
  }

  return newLines.join('\n')
}

/**
 * Fix disabled rules in a file (wrapper that reads/writes)
 */
function fixFile(filePath, actualIssues) {
  const { allRules: currentDisabledRules, preTodoRules } = extractDisabledRules(filePath)

  // Check if change is actually needed
  const actualIssuesSorted = actualIssues.sort()
  const currentRulesSorted = currentDisabledRules.sort()

  if (actualIssues.length === 0 && currentDisabledRules.length === 0) {
    return // Both empty - no change needed
  }

  if (
    actualIssues.length > 0 &&
    actualIssuesSorted.length === currentRulesSorted.length &&
    actualIssuesSorted.every((rule, index) => rule === currentRulesSorted[index])
  ) {
    return // Rules match exactly - no change needed
  }

  const content = fs.readFileSync(filePath, 'utf8')
  const fixedContent = fixDisabledRulesInContent(content, actualIssues, preTodoRules)
  fs.writeFileSync(filePath, fixedContent)
}

/**
 * Find all contract directories in the current working directory and its parents
 * Returns an array of directories containing Solidity files
 */
function findContractDirs() {
  const path = require('path')
  const currentDir = process.cwd()
  const contractDirs = []

  // Check if current directory has a contracts subdirectory
  if (fs.existsSync(path.join(currentDir, 'contracts'))) {
    contractDirs.push(path.join(currentDir, 'contracts'))
  }

  // If we're in a monorepo, look for packages/*/contracts
  const packagesDir = path.join(currentDir, 'packages')
  if (fs.existsSync(packagesDir)) {
    const packages = fs.readdirSync(packagesDir)
    for (const pkg of packages) {
      const pkgContractsDir = path.join(packagesDir, pkg, 'contracts')
      if (fs.existsSync(pkgContractsDir)) {
        contractDirs.push(pkgContractsDir)
      }
    }
  }

  return contractDirs
}

/**
 * Find all Solidity files in the given directories or files
 * @param {string[]} targets - Array of file or directory paths to search
 * @returns {string[]} Array of .sol file paths
 */
function findSolidityFiles(targets) {
  const files = []

  for (const target of targets) {
    const stat = fs.statSync(target)

    if (stat.isFile() && target.endsWith('.sol')) {
      files.push(target)
    } else if (stat.isDirectory()) {
      try {
        const result = execSync(`find "${target}" -name "*.sol" -type f`, {
          encoding: 'utf8',
        })
        const foundFiles = result
          .trim()
          .split('\n')
          .filter((f) => f)
        files.push(...foundFiles)
      } catch (error) {
        console.error(`Warning: Could not search directory ${target}:`, error.message)
      }
    }
  }

  return files
}

/**
 * Process all files that need TODO sections
 * @param {string[]} targets - Optional array of specific files or directories to check
 * @param {boolean} shouldFix - Whether to automatically fix issues
 */
function processAllFiles(targets = null, shouldFix = false) {
  let allFiles = []

  if (targets && targets.length > 0) {
    // Use provided targets
    allFiles = findSolidityFiles(targets)
    console.log(`Processing ${allFiles.length} Solidity files from provided targets...\n`)
  } else {
    // Auto-detect based on current directory
    const contractDirs = findContractDirs()

    if (contractDirs.length === 0) {
      console.error('Error: No contracts directories found.')
      console.error('Please run from a directory containing a "contracts" folder,')
      console.error('or provide specific files/directories to check.')
      process.exit(1)
    }

    console.log(`Found contract directories: ${contractDirs.join(', ')}\n`)
    allFiles = findSolidityFiles(contractDirs)
    console.log(`Processing ${allFiles.length} Solidity files...\n`)
  }

  if (allFiles.length === 0) {
    console.log('No Solidity files found.')
    return
  }

  let correctFiles = 0
  let incorrectFiles = 0
  let fixedFiles = 0
  let noIssuesFiles = 0

  for (const filePath of allFiles) {
    const actualIssues = getActualIssues(filePath)
    const { allRules: disabledRules } = extractDisabledRules(filePath)

    const extraRules = disabledRules.filter((rule) => !actualIssues.includes(rule))
    const missingRules = actualIssues.filter((rule) => !disabledRules.includes(rule))
    const isCorrect = extraRules.length === 0 && missingRules.length === 0

    if (actualIssues.length === 0 && disabledRules.length === 0) {
      // File has no issues and no TODO section - perfect
      console.log(`✅ ${filePath} (no issues)`)
      noIssuesFiles++
      correctFiles++
    } else if (actualIssues.length === 0 && disabledRules.length > 0) {
      // File has no issues but has TODO section - should remove it
      if (shouldFix) {
        fixFile(filePath, actualIssues)
        console.log(`🔧 ${filePath} - FIXED (removed unnecessary TODO)`)
        fixedFiles++
      } else {
        console.log(`❌ ${filePath}`)
        console.log(`   Should remove TODO section (no issues)`)
        console.log(`   Currently: [${disabledRules.join(', ')}]`)
        console.log()
        incorrectFiles++
      }
    } else if (isCorrect) {
      console.log(`✅ ${filePath}`)
      correctFiles++
    } else {
      if (shouldFix) {
        fixFile(filePath, actualIssues)
        console.log(`🔧 ${filePath} - FIXED`)
        fixedFiles++
      } else {
        console.log(`❌ ${filePath}`)

        if (extraRules.length > 0) {
          console.log(`   Extra rules (not needed): ${extraRules.join(', ')}`)
        }

        if (missingRules.length > 0) {
          console.log(`   Missing rules (needed): ${missingRules.join(', ')}`)
        }

        if (actualIssues.length === 0) {
          console.log(`   Should remove TODO section (no issues)`)
        } else {
          console.log(`   Should be: ${actualIssues.join(', ')}`)
        }

        console.log(`   Currently: [${disabledRules.join(', ')}]`)
        console.log()

        incorrectFiles++
      }
    }
  }

  console.log(`\nSummary:`)
  console.log(`✅ Correct: ${correctFiles}`)
  if (shouldFix) {
    console.log(`🔧 Fixed: ${fixedFiles}`)
  } else {
    console.log(`❌ Incorrect: ${incorrectFiles}`)
  }
  console.log(`📄 No issues: ${noIssuesFiles}`)
  console.log(`📊 Total: ${allFiles.length}`)

  if (!shouldFix && incorrectFiles > 0) {
    console.log(`\n💡 Tip: Run with --fix to automatically update the solhint-disable rules`)
    process.exit(1)
  }
}

/**
 * Main function
 */
function main() {
  const args = process.argv.slice(2)
  const shouldFix = args.includes('--fix')

  // Filter out flags to get file/directory targets
  const targets = args.filter((arg) => !arg.startsWith('--'))

  if (args.includes('--help') || args.includes('-h')) {
    console.log(`Usage: verify-solhint-disables.js [options] [files/directories...]

Options:
  --fix           Automatically fix incorrect solhint-disable rules
  --help, -h      Show this help message

Arguments:
  files/directories   Optional. Specific files or directories to check.
                     If not provided, auto-detects based on current directory:
                     - If in a package: checks that package's contracts
                     - If in monorepo root: checks all packages/*/contracts

Examples:
  # Check all contracts in current package
  verify-solhint-disables.js

  # Check all contracts in monorepo (from root)
  verify-solhint-disables.js

  # Check specific file
  verify-solhint-disables.js contracts/staking/Staking.sol

  # Check specific directory
  verify-solhint-disables.js contracts/staking

  # Auto-fix issues
  verify-solhint-disables.js --fix
`)
    return
  }

  if (shouldFix) {
    console.log('🔧 FIXING MODE: Will automatically update disabled rules\n')
  } else {
    console.log('🔍 VERIFICATION MODE: Use --fix to automatically update disabled rules\n')
  }

  processAllFiles(targets.length > 0 ? targets : null, shouldFix)
}

if (require.main === module) {
  main()
}

// Export for testing
module.exports = { extractDisabledRulesFromContent, fixDisabledRulesInContent }
