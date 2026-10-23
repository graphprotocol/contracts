#!/usr/bin/env node

import fs from 'node:fs'
import { fileURLToPath } from 'node:url'

function normalizePath(sf) {
  const parts = sf.split('/')
  const idx = parts.lastIndexOf('contracts')
  return idx === -1 ? sf : parts.slice(idx).join('/')
}

export function parseLcov(text) {
  const files = {}
  let current = null
  for (const line of text.split('\n')) {
    if (line.startsWith('SF:')) {
      const key = normalizePath(line.slice(3).trim())
      current = files[key] ??= { lines: new Map(), functions: new Set() }
    } else if (!current) {
      continue
    } else if (line.startsWith('DA:')) {
      const [num, hits] = line.slice(3).split(',')
      current.lines.set(num, (current.lines.get(num) ?? false) || Number(hits) > 0)
    } else if (line.startsWith('FNDA:')) {
      const rest = line.slice(5)
      const comma = rest.indexOf(',')
      const name = rest.slice(comma + 1).trim()
      if (Number(rest.slice(0, comma)) > 0 && name) current.functions.add(name)
    } else if (line.startsWith('end_of_record')) {
      current = null
    }
  }
  const result = {}
  for (const [key, { lines, functions }] of Object.entries(files)) {
    const linesFound = lines.size
    const linesHit = [...lines.values()].filter(Boolean).length
    const pct = linesFound === 0 ? null : Math.round((linesHit / linesFound) * 10000) / 100
    result[key] = { linesFound, linesHit, pct, functionsHit: [...functions].sort() }
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
