#!/usr/bin/env node
/**
 * Check for TODO comments in Solidity files.
 *
 * When called with file arguments: checks those specific files.
 * When called with no arguments: checks only git-changed files (modified/added/untracked).
 */

import { execSync } from 'child_process'
import { existsSync, readFileSync } from 'fs'
import { resolve } from 'path'

// Pattern to match TODO comments in Solidity
// Matches TODO, FIXME, XXX, HACK in both single-line and multi-line comments
const TODO_PATTERN = /\/\/.*\b(todo|fixme|xxx|hack)\b|\/\*.*\b(todo|fixme|xxx|hack)\b/gi

/**
 * Find TODO comments in a Solidity file.
 * @param {string} filePath - Path to the Solidity file
 * @returns {Array<{lineNumber: number, lineContent: string}>} Array of TODO matches
 */
function findTodosInFile(filePath) {
  const todos = []

  try {
    const content = readFileSync(filePath, 'utf-8')
    const lines = content.split('\n')

    lines.forEach((line, index) => {
      if (TODO_PATTERN.test(line)) {
        todos.push({
          lineNumber: index + 1,
          lineContent: line.trimEnd(),
        })
      }
      // Reset regex state for next iteration
      TODO_PATTERN.lastIndex = 0
    })
  } catch (error) {
    console.error(`⚠️  Error reading ${filePath}: ${error}`)
  }

  return todos
}

/**
 * Get locally changed Solidity files from git.
 * @returns {string[]} Array of changed .sol file paths
 */
function getGitChangedFiles() {
  try {
    // Get modified and added files
    const diffOutput = execSync('git diff --name-only --diff-filter=AM HEAD', {
      encoding: 'utf-8',
    }).trim()
    const changedFiles = diffOutput ? diffOutput.split('\n').filter((f) => f.endsWith('.sol')) : []

    // Get untracked files
    const untrackedOutput = execSync('git ls-files --others --exclude-standard', {
      encoding: 'utf-8',
    }).trim()
    const untrackedFiles = untrackedOutput ? untrackedOutput.split('\n').filter((f) => f.endsWith('.sol')) : []

    // Combine and filter empty strings
    return [...changedFiles, ...untrackedFiles].filter((f) => f)
  } catch {
    return []
  }
}

/**
 * Main entry point.
 * @returns {number} Exit code (0 = success, 1 = TODOs found)
 */
function main() {
  // Determine which files to check
  const hasFileArgs = process.argv.length > 2

  let filesToCheck
  if (hasFileArgs) {
    // Check specific files passed as arguments
    filesToCheck = process.argv.slice(2).filter((f) => f.endsWith('.sol'))
  } else {
    // Check only git-changed files
    filesToCheck = getGitChangedFiles()
    if (filesToCheck.length === 0) {
      console.log('✅ No locally changed or untracked Solidity files to check for TODO comments.')
      return 0
    }
  }

  if (filesToCheck.length === 0) {
    console.log('✅ No files to check for TODO comments.')
    return 0
  }

  // Check each file for TODOs
  let filesChecked = 0
  let filesWithTodos = 0
  let totalTodos = 0
  let todoFound = false

  for (const filePathStr of filesToCheck) {
    const filePath = resolve(filePathStr)

    // Only check if file exists and is a Solidity file
    if (!existsSync(filePath)) {
      continue
    }

    filesChecked++
    const todos = findTodosInFile(filePath)

    if (todos.length > 0) {
      if (!todoFound) {
        console.log('❌ TODO comments found in Solidity files:')
        console.log()
        todoFound = true
      }

      filesWithTodos++
      totalTodos += todos.length

      console.log(`📝 ${filePathStr}:`)
      for (const { lineNumber, lineContent } of todos) {
        console.log(`  ${lineNumber}: ${lineContent}`)
      }
      console.log()
    }
  }

  // Exit with appropriate message
  const fileType = hasFileArgs ? 'specified' : 'locally changed'
  const icon = todoFound ? '❌' : '✅'

  console.log(
    `${icon} Found ${totalTodos} TODO comment(s) in ${filesWithTodos}/${filesChecked} ${fileType} Solidity file(s).`,
  )

  return todoFound ? 1 : 0
}

// Run main and exit with appropriate code
process.exit(main())
