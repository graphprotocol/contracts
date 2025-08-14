#!/usr/bin/env node

const fs = require('fs')
const { execSync } = require('child_process')

/**
 * Extract solhint-disable rules from a file's TODO section
 */
function extractDisabledRules(filePath) {
  const content = fs.readFileSync(filePath, 'utf8')
  const lines = content.split('\n')

  let inTodoSection = false
  let disabledRules = []

  for (const line of lines) {
    // Handle TODO pattern
    if (line.includes('TODO: Re-enable and fix issues')) {
      inTodoSection = true
      continue
    }

    if (inTodoSection && line.trim().startsWith('// solhint-disable ')) {
      const rulesStr = line.replace('// solhint-disable ', '').trim().replace(/,$/, '')
      disabledRules = rulesStr
        .split(',')
        .map((r) => r.trim())
        .filter((r) => r)
      break
    }

    if (inTodoSection && !line.trim().startsWith('//')) {
      break
    }

    // Handle standalone solhint-disable
    if (!inTodoSection && line.trim().startsWith('// solhint-disable ')) {
      const rulesStr = line.replace('// solhint-disable ', '').trim().replace(/,$/, '')
      disabledRules = rulesStr
        .split(',')
        .map((rule) => rule.trim())
        .filter((rule) => rule.length > 0)
      break
    }
  }

  return disabledRules.sort()
}

/**
 * Get actual solhint issues for a file by sending content without TODO section via stdin
 */
function getActualIssues(filePath) {
  try {
    const content = fs.readFileSync(filePath, 'utf8')

    // Remove all lines starting with "// solhint-disable"
    const cleanedLines = []

    for (const line of content.split('\n')) {
      if (!line.trim().startsWith('// solhint-disable ')) {
        cleanedLines.push(line)
      }
    }

    const cleanedContent = cleanedLines.join('\n')

    // Write cleaned content to temporary file and run solhint from package root
    const tempFile = filePath.replace('.sol', '.temp.sol')
    fs.writeFileSync(tempFile, cleanedContent)

    try {
      const result = execSync(`npx solhint ${tempFile} -f json`, {
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
 * Fix disabled rules in a file
 */
function fixFile(filePath, actualIssues) {
  const currentDisabledRules = extractDisabledRules(filePath)

  // Check if change is actually needed
  const actualIssuesSorted = actualIssues.sort()
  const currentRulesSorted = currentDisabledRules.sort()

  if (actualIssues.length === 0 && currentDisabledRules.length === 0) {
    // Both empty - no change needed
    return
  }

  if (
    actualIssues.length > 0 &&
    actualIssuesSorted.length === currentRulesSorted.length &&
    actualIssuesSorted.every((rule, index) => rule === currentRulesSorted[index])
  ) {
    // Rules match exactly - no change needed
    return
  }
  const content = fs.readFileSync(filePath, 'utf8')
  const lines = content.split('\n')

  const newLines = []
  let inTodoSection = false
  let todoSectionEnded = false
  let pragmaEndIndex = -1

  // Find pragma end and TODO section
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]

    if (line.trim().startsWith('pragma ')) {
      pragmaEndIndex = i
    }

    if (line.includes('TODO: Re-enable and fix issues')) {
      inTodoSection = true
      continue
    }

    if (inTodoSection && line.trim().startsWith('// solhint-disable')) {
      continue // Skip old disable line
    }

    if (inTodoSection && !line.trim().startsWith('//')) {
      todoSectionEnded = true // TODO section has ended (moved past comments)
    }

    if (inTodoSection && todoSectionEnded && line.trim() !== '') {
      inTodoSection = false // No longer in TODO section when we hit non-blank
    }

    if (!inTodoSection) {
      newLines.push(line)
    }
  }

  // If no issues, remove TODO section entirely
  if (actualIssues.length === 0) {
    fs.writeFileSync(filePath, newLines.join('\n'))
    return
  }

  // Insert new TODO section after last pragma, skipping any existing blank lines
  let insertIndex = pragmaEndIndex + 1

  // Skip existing blank lines after pragma
  while (insertIndex < newLines.length && newLines[insertIndex].trim() === '') {
    insertIndex++
  }

  const todoSection = [
    '// TODO: Re-enable and fix issues when publishing a new version',
    `// solhint-disable ${actualIssues.join(', ')}`,
    '',
  ]

  newLines.splice(insertIndex, 0, ...todoSection)

  fs.writeFileSync(filePath, newLines.join('\n'))
}

/**
 * Process all files that need TODO sections
 */
function processAllFiles(shouldFix = false) {
  const contractsDir = 'contracts'

  // Find all .sol files
  const allFilesResult = execSync(`find ${contractsDir} -name "*.sol"`, {
    encoding: 'utf8',
  })

  const allFiles = allFilesResult
    .trim()
    .split('\n')
    .filter((f) => f)

  console.log(`Processing ${allFiles.length} Solidity files...\n`)

  let correctFiles = 0
  let incorrectFiles = 0
  let fixedFiles = 0
  let noIssuesFiles = 0

  for (const filePath of allFiles) {
    const actualIssues = getActualIssues(filePath)
    const disabledRules = extractDisabledRules(filePath)

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
    process.exit(1)
  }
}

/**
 * Main function
 */
function main() {
  const args = process.argv.slice(2)
  const shouldFix = args.includes('--fix')

  if (shouldFix) {
    console.log('🔧 FIXING MODE: Will automatically update disabled rules\n')
  } else {
    console.log('🔍 VERIFICATION MODE: Use --fix to automatically update disabled rules\n')
  }

  processAllFiles(shouldFix)
}

if (require.main === module) {
  main()
}
