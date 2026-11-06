#!/usr/bin/env node

import fs from 'node:fs'
import { fileURLToPath } from 'node:url'

const bare = (name) => {
  const noOverload = name.replace(/\.\d+$/, '')
  return noOverload.slice(noOverload.lastIndexOf('.') + 1)
}

export function compareCoverage(baseline, current, files) {
  const regressions = []
  const belowLines = []
  for (const file of files) {
    const base = baseline[file]
    if (!base) throw new Error(`${file} is not in the baseline`)
    const now = current[file]
    if (!now) {
      if (base.linesFound !== 0) regressions.push(`${file}: missing from current coverage`)
      continue
    }
    const hit = new Set(now.functionsHit.map(bare))
    const lost = base.functionsHit.filter((fn) => !hit.has(bare(fn)))
    if (lost.length > 0) regressions.push(`${file}: functions no longer hit: ${lost.join(', ')}`)
    if (base.pct !== null && (now.pct ?? 0) < base.pct) {
      belowLines.push(`${file}: lines ${now.pct}% < baseline ${base.pct}%`)
    }
  }
  return { regressions, belowLines }
}

function main() {
  const [baselinePath, currentPath, ...files] = process.argv.slice(2)
  if (!baselinePath || !currentPath || files.length === 0) {
    console.error('Usage: compare-coverage.mjs <baseline.json> <current.json> <file...>')
    process.exit(1)
  }
  const read = (p) => JSON.parse(fs.readFileSync(p, 'utf8'))
  const { regressions, belowLines } = compareCoverage(read(baselinePath), read(currentPath), files)
  console.log(`Regressions (${regressions.length}):`)
  for (const r of regressions) console.log(`  ${r}`)
  console.log(`Below baseline line percentage (${belowLines.length}):`)
  for (const l of belowLines) console.log(`  ${l}`)
  if (regressions.length > 0) process.exit(1)
}

if (fs.realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main()
}
