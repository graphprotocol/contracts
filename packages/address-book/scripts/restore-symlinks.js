#!/usr/bin/env node

/**
 * Restore Symlinks After Publishing
 *
 * Restores the dev-time symlinks under src/<name>/addresses.json after
 * npm publish. copy-addresses-for-publish.js replaces them with real files
 * for the publish step; this puts them back.
 */

const fs = require('fs')
const path = require('path')
const SOURCES = require('./sources')

const ROOT = path.resolve(__dirname, '..')
const SRC = path.join(ROOT, 'src')

function restoreOne(name) {
  const linkTarget = `../../../${name}/addresses.json`
  const linkDir = path.join(SRC, name)
  const linkPath = path.join(linkDir, 'addresses.json')

  fs.mkdirSync(linkDir, { recursive: true })
  fs.rmSync(linkPath, { force: true })
  fs.symlinkSync(linkTarget, linkPath)
  console.log(`✅ Restored symlink: src/${name}/addresses.json -> ${linkTarget}`)
}

function main() {
  console.log('🔗 Restoring symlinks after publish...')
  for (const name of SOURCES) restoreOne(name)
  console.log('✅ Symlinks restored!')
}

if (require.main === module) {
  main()
}
