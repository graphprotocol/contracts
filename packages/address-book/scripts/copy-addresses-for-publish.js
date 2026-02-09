#!/usr/bin/env node

/**
 * Copy Addresses for Publishing
 *
 * This script copies the actual addresses.json files from horizon and subgraph-service
 * packages to replace the symlinks before npm publish.
 *
 * Why we need this:
 * - Development uses symlinks (committed to git) for convenience
 * - npm publish doesn't include symlinks in the published package
 * - We need actual files in the published package for consumers
 *
 * The postpublish script will restore the symlinks after publishing.
 */

const fs = require('fs')
const path = require('path')

const FILES_TO_COPY = [
  {
    source: '../../../horizon/addresses.json',
    target: 'src/horizon/addresses.json',
  },
  {
    source: '../../../issuance/addresses.json',
    target: 'src/issuance/addresses.json',
  },
  {
    source: '../../../subgraph-service/addresses.json',
    target: 'src/subgraph-service/addresses.json',
  },
]

function copyFileForPublish(source, target) {
  const targetPath = path.resolve(__dirname, '..', target)
  const sourcePath = path.resolve(path.dirname(targetPath), source)

  // Ensure source exists
  if (!fs.existsSync(sourcePath)) {
    console.error(`❌ Source file ${sourcePath} does not exist`)
    process.exit(1)
  }

  // Remove existing symlink
  if (fs.existsSync(targetPath)) {
    fs.unlinkSync(targetPath)
  }

  // Copy actual file
  try {
    fs.copyFileSync(sourcePath, targetPath)
    console.log(`✅ Copied for publish: ${target} <- ${source}`)
  } catch (error) {
    console.error(`❌ Failed to copy ${source} to ${target}:`, error.message)
    process.exit(1)
  }
}

function main() {
  console.log('📦 Copying address files for npm publish...')

  for (const { source, target } of FILES_TO_COPY) {
    copyFileForPublish(source, target)
  }

  console.log('✅ Address files copied for publish!')
}

if (require.main === module) {
  main()
}
