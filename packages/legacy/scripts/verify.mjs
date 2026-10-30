#!/usr/bin/env node
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

import { checkSources, compareAddresses, compileBundle, normalizeRuntime, runtimeHash } from './lib.mjs'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const targets = JSON.parse(fs.readFileSync(path.join(root, 'targets.json'), 'utf8'))
const { contracts } = JSON.parse(fs.readFileSync(path.join(root, 'mainnet.json'), 'utf8'))
const folders = fs
  .readdirSync(path.join(root, 'verified'), { withFileTypes: true })
  .filter((entry) => entry.isDirectory())
  .map((entry) => entry.name)

const mismatches = []

const listed = { 'targets.json': Object.keys(targets), 'verified/': folders, 'mainnet.json': Object.keys(contracts) }
const all = new Set(Object.values(listed).flat())
for (const [where, names] of Object.entries(listed)) {
  for (const name of all) {
    if (!names.includes(name)) mismatches.push(`${name}: not in ${where}`)
  }
}

mismatches.push(...compareAddresses(targets, contracts))

for (const name of folders) {
  const dir = path.join(root, 'verified', name)
  for (const file of checkSources(dir)) mismatches.push(`${name}: source differs: ${file}`)
  const { object, ranges } = compileBundle(dir)
  if (runtimeHash(normalizeRuntime(object, ranges)) !== contracts[name]?.runtimeHash) {
    mismatches.push(`${name}: runtime code differs from mainnet.json`)
  }
}

if (mismatches.length) {
  for (const mismatch of mismatches) console.error(mismatch)
  process.exit(1)
}
console.log(`OK: ${folders.length} mainnet implementations reproduce`)
