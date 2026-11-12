#!/usr/bin/env node

/**
 * Create Symlinks After Publishing
 *
 * Turns src/<name>/addresses.json into symlinks to each package's
 * addresses.json after npm publish. The tracked files are regular files, so
 * the symlinks show as changes in git until `git checkout -- src` restores them.
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
