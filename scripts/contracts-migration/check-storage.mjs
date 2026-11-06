#!/usr/bin/env node
// Compares the storage layout of each ported contract with its committed pre-port (0.7.6) layout.
import { execFileSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

import { compareLayouts } from './compare-storage-layout.mjs'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..')

export const PORTED = [
  {
    pkg: 'packages/issuance',
    id: 'contracts/rewards/RewardsManager.sol:RewardsManager',
    fixture: 'test/fixtures/pre-port/RewardsManager.storage.json',
  },
  {
    pkg: 'packages/subgraph-service',
    id: 'contracts/l2/discovery/L2GNS.sol:L2GNS',
    fixture: 'test/fixtures/pre-port/L2GNS.storage.json',
  },
  {
    pkg: 'packages/subgraph-service',
    id: 'contracts/l2/curation/L2Curation.sol:L2Curation',
    fixture: 'test/fixtures/pre-port/L2Curation.storage.json',
  },
]

let failed = false
for (const { pkg, id, fixture } of PORTED) {
  const cwd = path.join(root, pkg)
  const before = JSON.parse(fs.readFileSync(path.join(cwd, fixture), 'utf8'))
  const after = JSON.parse(execFileSync('forge', ['inspect', id, 'storageLayout', '--json'], { cwd, encoding: 'utf8' }))
  const diffs = compareLayouts(before, after)
  if (diffs.length) {
    failed = true
    console.error(`${id}:`)
    for (const d of diffs) console.error(`  ${d}`)
  }
}
if (failed) process.exit(1)
console.log(`OK: ${PORTED.length} storage layouts match`)
