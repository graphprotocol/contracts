#!/usr/bin/env node

/**
 * Extract essential GraphClient artifacts for offline builds
 *
 * This script extracts only the minimal TypeScript types and query documents
 * needed for compilation from the full GraphClient build output.
 *
 * Benefits:
 * - Enables builds without STUDIO_API_KEY (extracted files ~few KB vs full download ~hundreds of KB)
 * - Prevents git repository bloat from large GraphClient artifacts
 * - Provides build stability without external API dependency
 *
 * Output is deterministic (sorted types, formatted) to prevent git thrash.
 * See README.md "Build Process" section for details.
 */

const fs = require('fs')
const path = require('path')

// Paths
const graphClientDir = '.graphclient'
const extractedDir = '.graphclient-extracted'
const graphClientIndex = path.join(graphClientDir, 'index.js')
const graphClientTypes = path.join(graphClientDir, 'index.d.ts')

// Helper functions
const fileExists = (filePath) => fs.existsSync(filePath)
const ensureDir = (dirPath) => {
  if (!fs.existsSync(dirPath)) {
    fs.mkdirSync(dirPath, { recursive: true })
  }
}

// Create minimal self-contained GraphClient artifacts
function createMinimalArtifacts() {
  if (!fileExists(graphClientTypes)) {
    throw new Error('GraphClient types not found. Run GraphClient build first.')
  }

  // Read the original files
  const originalTypes = fs.readFileSync(graphClientTypes, 'utf8')
  const originalJs = fs.readFileSync(graphClientIndex, 'utf8')

  // Extract only the specific types we need
  const neededTypes = [
    'TokenLockWallet',
    'GraphNetwork',
    'GraphAccount',
    'Indexer',
    'Curator',
    'Delegator',
    'CuratorWalletsQuery',
    'GraphAccountQuery',
    'GraphNetworkQuery',
    'TokenLockWalletsQuery',
    'Maybe',
    'InputMaybe',
    'Scalars',
  ]

  // Extract only the query documents we need
  const neededQueries = [
    'CuratorWalletsDocument',
    'GraphAccountDocument',
    'GraphNetworkDocument',
    'TokenLockWalletsDocument',
  ]

  // Create minimal types file
  const minimalTypes = extractSpecificTypes(originalTypes, neededTypes)

  // Create minimal JS file
  const minimalJs = createMinimalJs(originalJs, neededQueries)

  return { types: minimalTypes, js: minimalJs }
}

// Extract specific types from the original types file
function extractSpecificTypes(content, neededTypes) {
  const lines = content.split('\n')
  const extractedTypes = new Map() // Store types by name for sorting
  let currentType = null
  let currentTypeLines = []
  let braceDepth = 0
  let inNeededType = false

  for (const line of lines) {
    // Check if this starts a type we need
    const typeMatch = line.match(/export (?:type|interface) (\w+)/)
    if (typeMatch) {
      // Save previous type if we were extracting one
      if (inNeededType && currentType) {
        extractedTypes.set(currentType, currentTypeLines.join('\n'))
      }

      currentType = typeMatch[1]
      if (neededTypes.includes(currentType)) {
        inNeededType = true
        currentTypeLines = [line]
        braceDepth = 0
        braceDepth += (line.match(/{/g) || []).length
        braceDepth -= (line.match(/}/g) || []).length
        if (line.trim().endsWith(';') && braceDepth === 0) {
          extractedTypes.set(currentType, currentTypeLines.join('\n'))
          inNeededType = false
        }
      } else {
        inNeededType = false
        currentTypeLines = []
      }
      continue
    }

    if (inNeededType) {
      currentTypeLines.push(line)
      braceDepth += (line.match(/{/g) || []).length
      braceDepth -= (line.match(/}/g) || []).length
      if (braceDepth === 0 && (line.trim().endsWith(';') || line.trim().endsWith('}'))) {
        extractedTypes.set(currentType, currentTypeLines.join('\n'))
        inNeededType = false
        currentTypeLines = []
      }
    }
  }

  // Sort types alphabetically by name and join with blank line separator
  const sortedTypes = Array.from(extractedTypes.entries())
    .sort(([nameA], [nameB]) => nameA.localeCompare(nameB))
    .map(([, typeContent]) => typeContent)
    .join('\n')

  return sortedTypes
}

// Create minimal JS with only needed queries
function createMinimalJs(content, neededQueries) {
  // Extract only the queries we need
  const queryRegex = /exports\.(.*Document)\s*=\s*\(0,\s*utils_1\.gql\)\s*`([\s\S]*?)`\s*;/g
  const extractedQueries = []
  let match

  while ((match = queryRegex.exec(content)) !== null) {
    const [, docName, query] = match
    if (neededQueries.includes(docName)) {
      extractedQueries.push(`exports.${docName} = gql\`${query}\`;`)
    }
  }

  return `"use strict";
Object.defineProperty(exports, "__esModule", { value: true });

// Minimal GraphClient for offline builds - contains only what ops/info.ts uses
// Simple gql template literal function (replacement for @graphql-mesh/utils)
const gql = (strings, ...values) => {
  let result = strings[0];
  for (let i = 0; i < values.length; i++) {
    result += values[i] + strings[i + 1];
  }
  return result;
};

// Mock execute function
const execute = () => {
  throw new Error('GraphClient execute() requires API key. This is an offline build with cached types only.');
};
exports.execute = execute;

// Only the query documents actually used
${extractedQueries.join('\n\n')}

// Mock SDK
function getSdk() {
  return {
    GraphAccount: () => execute(),
    CuratorWallets: () => execute(),
    GraphNetwork: () => execute(),
    TokenLockWallets: () => execute(),
  };
}
exports.getSdk = getSdk;
`
}

// The compilation approach handles both types and runtime code together
// No separate query extraction needed

// Main extract function
async function extract() {
  // Ensure extracted directory exists
  ensureDir(extractedDir)

  try {
    // Create minimal self-contained artifacts (only types/queries used by ops/info.ts)
    const artifacts = createMinimalArtifacts()

    // Write the minimal types and runtime code
    const typesPath = path.join(extractedDir, 'index.d.ts')
    const jsPath = path.join(extractedDir, 'index.js')
    fs.writeFileSync(typesPath, artifacts.types)
    fs.writeFileSync(jsPath, artifacts.js)

    // Format with prettier for consistent output
    const { execSync } = require('child_process')
    try {
      const pkgRoot = path.resolve(__dirname, '..')
      execSync(`npx prettier --write "${typesPath}" "${jsPath}"`, {
        cwd: pkgRoot,
        stdio: 'inherit',
      })
      console.log(`✅ Extracted and formatted minimal artifacts to ${extractedDir}/`)
    } catch {
      console.warn('⚠️  Prettier formatting failed, but extraction succeeded')
      console.log(`✅ Extracted minimal artifacts to ${extractedDir}/`)
    }
  } catch (error) {
    console.error('❌ Extraction failed:', error.message)
    process.exit(1)
  }
}

// Run if called directly
if (require.main === module) {
  extract()
}

module.exports = { extract }
