#!/usr/bin/env node
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

import { sha256 } from './lib.mjs'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const SOURCIFY = 'https://sourcify.dev/server/v2/contract/1'

async function fetchBundle(implementation) {
  const response = await fetch(`${SOURCIFY}/${implementation}?fields=stdJsonInput,compilation`)
  if (!response.ok) throw new Error(`sourcify ${implementation}: HTTP ${response.status}`)
  return response.json()
}

function writeBundle(name, { match, stdJsonInput, compilation }) {
  if (!match) throw new Error(`${name}: not verified on Sourcify`)
  const dir = path.join(root, 'verified', name)
  const sourcesDir = path.join(dir, 'sources')
  fs.rmSync(dir, { recursive: true, force: true })

  const sourceHashes = {}
  for (const [file, { content }] of Object.entries(stdJsonInput.sources)) {
    const dest = path.resolve(sourcesDir, file)
    if (!dest.startsWith(sourcesDir + path.sep)) throw new Error(`${name}: unsafe source path ${file}`)
    fs.mkdirSync(path.dirname(dest), { recursive: true })
    fs.writeFileSync(dest, content)
    sourceHashes[file] = sha256(fs.readFileSync(dest))
  }

  const { outputSelection: _, ...settings } = stdJsonInput.settings
  const split = compilation.fullyQualifiedName.lastIndexOf(':')
  const compiler = {
    version: compilation.compilerVersion,
    settings,
    target: {
      source: compilation.fullyQualifiedName.slice(0, split),
      name: compilation.fullyQualifiedName.slice(split + 1),
    },
    sourcifyMatch: match,
    sourceHashes,
  }
  fs.writeFileSync(path.join(dir, 'compiler.json'), JSON.stringify(compiler, null, 2) + '\n')
  console.log(`${name}: ${Object.keys(sourceHashes).length} files, ${match}, ${compiler.version}`)
}

const targets = JSON.parse(fs.readFileSync(path.join(root, 'targets.json'), 'utf8'))
for (const [name, { implementation }] of Object.entries(targets)) {
  writeBundle(name, await fetchBundle(implementation))
}
