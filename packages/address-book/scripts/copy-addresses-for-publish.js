#!/usr/bin/env node

/**
 * Copy Addresses for Publishing
 *
 * Replaces the dev-time symlinks under src/<name>/addresses.json with real
 * file copies before npm publish — npm does not include symlinks in the
 * published tarball. restore-symlinks.js puts the symlinks back afterwards.
 */

const fs = require('fs')
const path = require('path')
const SOURCES = require('./sources')

const ROOT = path.resolve(__dirname, '..')
const SRC = path.join(ROOT, 'src')

function copyOne(name) {
  const sourcePath = path.resolve(ROOT, '..', name, 'addresses.json')
  const targetDir = path.join(SRC, name)
  const targetPath = path.join(targetDir, 'addresses.json')

  if (!fs.existsSync(sourcePath)) {
    console.error(`❌ Source file ${sourcePath} does not exist`)
    process.exit(1)
  }

  fs.mkdirSync(targetDir, { recursive: true })
  fs.rmSync(targetPath, { force: true })
  fs.copyFileSync(sourcePath, targetPath)
  console.log(`✅ Copied for publish: src/${name}/addresses.json`)
}

function checkDrift() {
  const dirs = fs
    .readdirSync(SRC)
    .filter((d) => fs.statSync(path.join(SRC, d)).isDirectory())
    .sort()
  const expected = [...SOURCES].sort()
  if (JSON.stringify(dirs) !== JSON.stringify(expected)) {
    console.error(`❌ Drift between SOURCES and src/`)
    console.error(`   SOURCES: [${expected.join(', ')}]`)
    console.error(`   src/   : [${dirs.join(', ')}]`)
    process.exit(1)
  }
}

function main() {
  console.log('📦 Copying address files for npm publish...')
  for (const name of SOURCES) copyOne(name)
  checkDrift()
  console.log('✅ Address files copied for publish!')
}

if (require.main === module) {
  main()
}
