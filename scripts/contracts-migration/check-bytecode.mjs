#!/usr/bin/env node
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { parseArgs } from 'node:util'

import { bytecodeHash } from '../lib/bytecode.mjs'

const here = path.dirname(fileURLToPath(import.meta.url))
const FIELDS = ['bytecode', 'deployedBytecode']

export function computeHashes(manifest, repoRoot) {
  const hashes = {}
  const missing = []
  const empty = []
  for (const [name, rel] of Object.entries(manifest)) {
    const file = path.join(repoRoot, rel)
    if (!fs.existsSync(file)) {
      missing.push(rel)
      continue
    }
    const artifact = JSON.parse(fs.readFileSync(file, 'utf8'))
    if (FIELDS.some((f) => !artifact[f] || artifact[f] === '0x')) {
      empty.push(name)
      continue
    }
    hashes[name] = Object.fromEntries(FIELDS.map((f) => [f, bytecodeHash(artifact[f])]))
  }
  return { hashes, missing, empty }
}

export function compare(reference, hashes) {
  const lines = []
  for (const name of Object.keys(reference)) {
    if (!(name in hashes)) {
      lines.push(`${name}: not in manifest`)
      continue
    }
    for (const f of FIELDS) {
      if (reference[name][f] !== hashes[name][f]) lines.push(`${name}: ${f} differs`)
    }
  }
  for (const name of Object.keys(hashes)) {
    if (!(name in reference)) lines.push(`${name}: not in reference`)
  }
  return lines
}

function main() {
  const { values } = parseArgs({
    options: {
      root: { type: 'string', default: path.resolve(here, '../..') },
      manifest: { type: 'string', default: path.join(here, 'manifest.json') },
      reference: { type: 'string', default: path.join(here, 'reference.json') },
      write: { type: 'boolean', default: false },
    },
  })
  const manifest = JSON.parse(fs.readFileSync(values.manifest, 'utf8'))
  const { hashes, missing, empty } = computeHashes(manifest, values.root)

  if (missing.length || empty.length) {
    for (const m of missing) console.error(`missing artifact: ${m}`)
    for (const e of empty) console.error(`empty bytecode: ${e}`)
    process.exit(1)
  }

  if (values.write) {
    const sorted = Object.fromEntries(Object.entries(hashes).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)))
    fs.writeFileSync(values.reference, JSON.stringify(sorted, null, 2) + '\n')
    return
  }

  const reference = JSON.parse(fs.readFileSync(values.reference, 'utf8'))
  const diffs = compare(reference, hashes)
  if (diffs.length) {
    for (const d of diffs) console.error(d)
    process.exit(1)
  }
  console.log(`OK: ${Object.keys(hashes).length} contracts match`)
}

if (fs.realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) main()
