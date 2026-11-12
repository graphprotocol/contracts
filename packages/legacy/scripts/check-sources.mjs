#!/usr/bin/env node
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

import { checkSources } from './lib.mjs'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'verified')
const bundles = fs
  .readdirSync(root, { withFileTypes: true })
  .filter((entry) => entry.isDirectory())
  .map((entry) => entry.name)
if (!bundles.length) throw new Error(`no bundles found under ${root}`)

const mismatches = bundles.flatMap((name) =>
  checkSources(path.join(root, name)).map((file) => `${name}: source differs: ${file}`),
)

if (mismatches.length) {
  for (const mismatch of mismatches) console.error(mismatch)
  process.exit(1)
}
console.log(`OK: ${bundles.length} bundles match their source hashes`)
