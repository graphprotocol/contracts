#!/usr/bin/env node

import fs from 'node:fs'
import { fileURLToPath } from 'node:url'

function normalizePath(sf) {
  const parts = sf.split('/')
  const idx = parts.lastIndexOf('contracts')
  return idx === -1 ? sf : parts.slice(idx).join('/')
}

export function parseLcov(text) {
  const result = {}
  let current = null
  for (const line of text.split('\n')) {
    if (line.startsWith('SF:')) {
      current = { key: normalizePath(line.slice(3).trim()), linesFound: 0, linesHit: 0 }
    } else if (!current) {
      continue
    } else if (line.startsWith('LF:')) {
      current.linesFound = Number(line.slice(3))
    } else if (line.startsWith('LH:')) {
      current.linesHit = Number(line.slice(3))
    } else if (line.startsWith('end_of_record')) {
      const { key, linesFound, linesHit } = current
      const pct = linesFound === 0 ? null : Math.round((linesHit / linesFound) * 10000) / 100
      result[key] = { linesFound, linesHit, pct }
      current = null
    }
  }
  return result
}

function main() {
  const [lcovPath, outPath] = process.argv.slice(2)
  if (!lcovPath || !outPath) {
    console.error('Usage: summarize-coverage.mjs <lcov.info> <out.json>')
    process.exit(1)
  }
  const parsed = parseLcov(fs.readFileSync(lcovPath, 'utf8'))
  const sorted = Object.fromEntries(
    Object.keys(parsed)
      .sort()
      .map((k) => [k, parsed[k]]),
  )
  fs.writeFileSync(outPath, JSON.stringify(sorted, null, 2) + '\n')
}

if (fs.realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main()
}
