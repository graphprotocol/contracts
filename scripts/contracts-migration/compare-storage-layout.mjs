#!/usr/bin/env node
// Compares two `forge inspect <C> storageLayout --json` outputs, ignoring astId, contract and type ids.
import fs from 'node:fs'
import { fileURLToPath } from 'node:url'

const TYPE_FIELDS = ['label', 'encoding', 'numberOfBytes']

function compareEntries(before, after, path, out, seen) {
  const n = Math.max(before.storage.length, after.storage.length)
  for (let i = 0; i < n; i++) {
    const b = before.storage[i]
    const a = after.storage[i]
    if (!b || !a) {
      out.push(`${path}[${i}] ${(b ?? a).label}: ${b ? 'removed' : 'added'}`)
      continue
    }
    const where = `${path}[${i}] ${b.label}`
    for (const f of ['label', 'slot', 'offset']) {
      if (String(b[f]) !== String(a[f])) out.push(`${where}: ${f} ${b[f]} -> ${a[f]}`)
    }
    compareTypes(before.types, b.type, after.types, a.type, where, out, seen)
  }
}

function compareTypes(beforeTypes, bId, afterTypes, aId, path, out, seen) {
  const key = `${bId}|${aId}`
  if (seen.has(key)) return
  seen.add(key)
  const b = beforeTypes[bId]
  const a = afterTypes[aId]
  if (!b || !a) {
    if (b !== a) out.push(`${path}: type ${bId} -> ${aId} missing`)
    return
  }
  for (const f of TYPE_FIELDS) {
    if (String(b[f]) !== String(a[f])) out.push(`${path}: type ${f} ${b[f]} -> ${a[f]}`)
  }
  for (const f of ['key', 'value', 'base']) {
    if (!b[f] && !a[f]) continue
    compareTypes(beforeTypes, b[f], afterTypes, a[f], `${path}.${f}`, out, seen)
  }
  if (b.members || a.members) {
    compareEntries(
      { storage: b.members ?? [], types: beforeTypes },
      { storage: a.members ?? [], types: afterTypes },
      `${path}.members`,
      out,
      seen,
    )
  }
}

export function compareLayouts(before, after) {
  const out = []
  compareEntries(
    { storage: before.storage, types: before.types ?? {} },
    { storage: after.storage, types: after.types ?? {} },
    'storage',
    out,
    new Set(),
  )
  return out
}

function main() {
  const [beforePath, afterPath] = process.argv.slice(2)
  if (!beforePath || !afterPath) {
    console.error('usage: compare-storage-layout.mjs <before.json> <after.json>')
    process.exit(2)
  }
  const read = (p) => JSON.parse(fs.readFileSync(p, 'utf8'))
  const diffs = compareLayouts(read(beforePath), read(afterPath))
  for (const d of diffs) console.log(d)
  if (diffs.length) process.exit(1)
  console.log('OK: storage layouts match')
}

if (fs.realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) main()
