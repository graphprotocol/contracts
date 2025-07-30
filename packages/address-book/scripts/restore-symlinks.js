#!/usr/bin/env node

/**
 * Restore Symlinks After Publishing
 *
 * This script restores the symlinks after npm publish completes.
 * The prepublishOnly script replaces symlinks with actual files for publishing,
 * and this script puts the symlinks back for development.
 */

const fs = require('fs')
const path = require('path')

const SYMLINKS_TO_RESTORE = [
  {
    target: '../../../horizon/addresses.json',
    link: 'src/horizon/addresses.json',
  },
  {
    target: '../../../subgraph-service/addresses.json',
    link: 'src/subgraph-service/addresses.json',
  },
]

function restoreSymlink(target, link) {
  const linkPath = path.resolve(__dirname, '..', link)

  // Remove the copied file
  if (fs.existsSync(linkPath)) {
    fs.unlinkSync(linkPath)
  }

  // Restore symlink
  try {
    fs.symlinkSync(target, linkPath)
    console.log(`✅ Restored symlink: ${link} -> ${target}`)
  } catch (error) {
    console.error(`❌ Failed to restore symlink ${link}:`, error.message)
    process.exit(1)
  }
}

function main() {
  console.log('🔗 Restoring symlinks after publish...')

  for (const { target, link } of SYMLINKS_TO_RESTORE) {
    restoreSymlink(target, link)
  }

  console.log('✅ Symlinks restored!')
}

if (require.main === module) {
  main()
}
