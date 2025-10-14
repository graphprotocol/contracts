#!/usr/bin/env node

/**
 * Extract essential GraphClient artifacts for offline builds
 *
 * This script extracts only the minimal TypeScript types and query documents
 * needed for compilation from the full GraphClient build output.
 * The extracted files are small and can be committed to git.
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
  const result = []
  let currentType = null
  let braceDepth = 0
  let inNeededType = false

  // Always include imports and utility types
  for (const line of lines) {
    if (line.includes('import ') || line.includes('export {')) {
      result.push(line)
      continue
    }

    // Check if this starts a type we need
    const typeMatch = line.match(/export (?:type|interface) (\w+)/)
    if (typeMatch) {
      currentType = typeMatch[1]
      if (neededTypes.includes(currentType)) {
        inNeededType = true
        braceDepth = 0
        result.push(line)
        braceDepth += (line.match(/{/g) || []).length
        braceDepth -= (line.match(/}/g) || []).length
        if (line.trim().endsWith(';') && braceDepth === 0) {
          inNeededType = false
        }
        continue
      } else {
        inNeededType = false
        continue
      }
    }

    if (inNeededType) {
      result.push(line)
      braceDepth += (line.match(/{/g) || []).length
      braceDepth -= (line.match(/}/g) || []).length
      if (braceDepth === 0 && (line.trim().endsWith(';') || line.trim().endsWith('}'))) {
        inNeededType = false
      }
    }
  }

  return result.join('\n')
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
    fs.writeFileSync(path.join(extractedDir, 'index.d.ts'), artifacts.types)
    fs.writeFileSync(path.join(extractedDir, 'index.js'), artifacts.js)

    console.log(`✅ Extracted minimal artifacts to ${extractedDir}/`)
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
