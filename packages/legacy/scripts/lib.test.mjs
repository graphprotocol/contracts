import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { test } from 'node:test'
import { fileURLToPath } from 'node:url'

import { checkSources } from './lib.mjs'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const BRIDGE_ESCROW_DIR = path.join(root, 'verified/BridgeEscrow')

const targetSource = (dir) => JSON.parse(fs.readFileSync(path.join(dir, 'compiler.json'), 'utf8')).target.source

function copyBundle(t) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'legacy-test-'))
  t.after(() => fs.rmSync(tmp, { recursive: true, force: true }))
  const dir = path.join(tmp, 'BridgeEscrow')
  fs.cpSync(BRIDGE_ESCROW_DIR, dir, { recursive: true })
  return dir
}

function editTarget(dir, edit) {
  const file = path.join(dir, 'sources', targetSource(dir))
  const before = fs.readFileSync(file, 'utf8')
  const after = edit(before)
  assert.notEqual(after, before)
  fs.writeFileSync(file, after)
}

test('a comment-only change fails the source check', (t) => {
  const dir = copyBundle(t)
  assert.deepEqual(checkSources(dir), [])
  editTarget(dir, (src) => `${src}// comment\n`)
  assert.deepEqual(checkSources(dir), [targetSource(dir)])
})

test('checkSources reports missing and extra files', (t) => {
  const dir = copyBundle(t)
  fs.rmSync(path.join(dir, 'sources', targetSource(dir)))
  fs.writeFileSync(path.join(dir, 'sources/extra.sol'), '')
  assert.deepEqual(checkSources(dir).sort(), ['extra.sol', targetSource(dir)].sort())
})
