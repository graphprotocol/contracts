/**
 * Root ESLint configuration for The Graph projects
 * This configuration is automatically picked up by ESLint
 */

import { existsSync, readFileSync } from 'node:fs'
import path from 'node:path'

import eslint from '@eslint/js'
import typescriptPlugin from '@typescript-eslint/eslint-plugin'
import prettier from 'eslint-config-prettier'
import importPlugin from 'eslint-plugin-import'
import jsdocPlugin from 'eslint-plugin-jsdoc'
import noOnlyTests from 'eslint-plugin-no-only-tests'
import simpleImportSort from 'eslint-plugin-simple-import-sort'
import unusedImportsPlugin from 'eslint-plugin-unused-imports'
import globals from 'globals'

// Function to find the Git repository root by looking for .git directory
function findRepoRoot(startDir) {
  let currentDir = startDir

  // Traverse up the directory tree until we find .git or reach the filesystem root
  while (currentDir !== path.parse(currentDir).root) {
    if (existsSync(path.join(currentDir, '.git'))) {
      return currentDir
    }
    currentDir = path.dirname(currentDir)
  }

  // If we couldn't find .git, return the starting directory
  return startDir
}

// Function to translate .gitignore patterns to ESLint glob patterns
function translateGitignorePatterns(gitignorePath, repoRoot) {
  try {
    const content = readFileSync(gitignorePath, 'utf8')
    const originalPatterns = content.split('\n').filter((line) => line.trim() && !line.startsWith('#'))

    // Filter out negation patterns for now as ESLint doesn't handle them correctly
    const nonNegationPatterns = originalPatterns.filter((line) => !line.startsWith('!'))

    const translatedPatterns = nonNegationPatterns.map((line) => {
      // Convert .gitignore patterns to ESLint glob patterns
      // Preserve the distinction between patterns:
      // - dirname/ (matches at any level) -> **/dirname/
      // - /dirname/ (matches only at root) -> /absolute/path/to/repo/dirname/
      if (line.startsWith('/')) {
        // Root-level pattern - convert to absolute path relative to repo root
        // This ensures it works correctly regardless of where ESLint is invoked from
        return path.join(repoRoot, line.substring(1))
      } else {
        // Any-level pattern, add **/ prefix if not already there
        return line.startsWith('**/') ? line : `**/${line}`
      }
    })

    // Create a mapping of original to translated patterns for debugging
    const patternMap = {}
    originalPatterns.forEach((pattern) => {
      if (pattern.startsWith('!')) {
        patternMap[pattern] = `[NEGATION PATTERN - NOT SUPPORTED BY ESLINT]`
      } else {
        const index = nonNegationPatterns.indexOf(pattern)
        if (index !== -1) {
          patternMap[pattern] = translatedPatterns[index]
        }
      }
    })

    return {
      originalPatterns,
      translatedPatterns,
      patternMap,
    }
  } catch (error) {
    console.warn(`Could not read .gitignore file: ${error.message}`)
    return {
      originalPatterns: [],
      translatedPatterns: [],
      patternMap: {},
    }
  }
}

// Function to include .gitignore patterns in ESLint config
function includeGitignore() {
  // Get the repository root directory (where .git is located)
  // This ensures patterns are resolved correctly regardless of where ESLint is invoked from
  const repoRoot = findRepoRoot(path.resolve('.'))
  const gitignorePath = path.join(repoRoot, '.gitignore')

  // Translate the patterns
  const { originalPatterns, translatedPatterns, patternMap } = translateGitignorePatterns(gitignorePath, repoRoot)

  // Debug output if DEBUG_GITIGNORE environment variable is set
  if (process.env.DEBUG_GITIGNORE) {
    console.log('\n=== .gitignore Pattern Translations ===')
    console.log('Repository root:', repoRoot)
    console.log('Pattern mappings:')

    // Count negation patterns
    const negationPatterns = originalPatterns.filter((p) => p.startsWith('!')).length
    if (negationPatterns > 0) {
      console.log(`\n  WARNING: Found ${negationPatterns} negation patterns in .gitignore.`)
      console.log('  Negation patterns (starting with !) are not supported by ESLint and will be ignored.')
      console.log('  Files matching these patterns will still be ignored.\n')
    }

    Object.entries(patternMap).forEach(([original, translated]) => {
      console.log(`  ${original} -> ${translated}`)
    })
    console.log('=======================================\n')
  }

  return {
    ignores: translatedPatterns,
  }
}

// Export the translation function for use in other contexts
export function getGitignorePatterns(customGitignorePath = null) {
  const repoRoot = findRepoRoot(path.resolve('.'))
  const gitignorePath = customGitignorePath || path.join(repoRoot, '.gitignore')
  return translateGitignorePatterns(gitignorePath, repoRoot)
}

export default [
  // Include .gitignore patterns
  includeGitignore(),

  eslint.configs.recommended,

  // Import plugin configuration
  {
    plugins: {
      import: importPlugin,
      'simple-import-sort': simpleImportSort,
    },
    rules: {
      // Turn off the original import/order rule
      'import/order': 'off',
      // Configure simple-import-sort and set to 'error' to enforce sorting
      'simple-import-sort/imports': 'error',
      'simple-import-sort/exports': 'error',
    },
  },

  // Unused imports plugin configuration
  {
    plugins: {
      'unused-imports': unusedImportsPlugin,
    },
    rules: {
      'unused-imports/no-unused-imports': 'warn',
    },
  },

  // JSDoc plugin configuration
  {
    plugins: {
      jsdoc: jsdocPlugin,
    },
    rules: {
      'jsdoc/require-jsdoc': 'off',
      'jsdoc/require-param': 'off',
      'jsdoc/require-returns': 'off',
      'jsdoc/require-description': 'off',
    },
  },

  // Custom config for TypeScript files
  {
    files: ['**/*.ts', '**/*.tsx'],
    languageOptions: {
      parser: (await import('@typescript-eslint/parser')).default,
      parserOptions: {
        ecmaVersion: 2022,
        sourceType: 'module',
      },
      globals: {
        ...globals.node,
      },
    },
    plugins: {
      '@typescript-eslint': typescriptPlugin,
      'no-only-tests': noOnlyTests,
    },
    rules: {
      'prefer-const': 'warn',
      'no-only-tests/no-only-tests': 'error',
      '@typescript-eslint/no-explicit-any': 'warn',
      '@typescript-eslint/ban-ts-comment': 'warn',
      'no-unused-vars': 'off', // Turn off base rule
      '@typescript-eslint/no-unused-vars': [
        'error',
        {
          varsIgnorePattern: '^_|Null|Active|Closed|graph|_i',
          argsIgnorePattern: '^_',
          caughtErrorsIgnorePattern: '^_',
        },
      ],
    },
  },

  // Custom config for JavaScript files
  {
    files: ['**/*.js', '**/*.cjs', '**/*.mjs', '**/*.jsx'],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'module',
      globals: {
        ...globals.node,
      },
    },
    plugins: {
      'no-only-tests': noOnlyTests,
    },
    rules: {
      'prefer-const': 'warn',
      'no-only-tests/no-only-tests': 'error',
      'no-unused-vars': [
        'error',
        {
          varsIgnorePattern: '^_|Null|Active|Closed|graph|_i',
          argsIgnorePattern: '^_',
        },
      ],
    },
  },

  // Add Mocha globals for test files
  {
    files: ['**/*.test.ts', '**/*.test.js', '**/test/**/*.ts', '**/test/**/*.js'],
    languageOptions: {
      globals: {
        ...globals.mocha,
      },
    },
  },

  // Add Hardhat globals for hardhat config files
  {
    files: ['**/hardhat.config.ts', '**/hardhat.config.js', '**/tasks/**/*.ts', '**/tasks/**/*.js'],
    languageOptions: {
      globals: {
        ...globals.node,
        task: 'readonly',
        HardhatUserConfig: 'readonly',
      },
    },
  },

  // Prettier configuration (to avoid conflicts)
  prettier,

  // Additional global ignores and unignores
  {
    ignores: [
      // Autogenerated GraphClient files (committed but should not be linted)
      '**/.graphclient-extracted/**',
      '**/.graphclient/**',
      // Third-party dependencies (Forge libraries, etc.)
      '**/lib/**',
    ],
  },

  // Explicitly include packages that should be linted
  {
    files: ['packages/**/*.{js,ts,cjs,mjs,jsx,tsx}'],
  },
]