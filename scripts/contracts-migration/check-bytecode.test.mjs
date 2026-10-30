import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { test } from 'node:test'
import { fileURLToPath } from 'node:url'

import { stripMetadata } from '../lib/bytecode.mjs'
import { compare, computeHashes } from './check-bytecode.mjs'

const script = path.join(path.dirname(fileURLToPath(import.meta.url)), 'check-bytecode.mjs')
const META_A = 'a264697066735822' + '1220' + 'ab'.repeat(32) + '64736f6c63430007060033'
const META_B = 'a264697066735822' + '1220' + 'cd'.repeat(32) + '64736f6c63430007060033'

function fixture(artifacts) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'bytecode-check-'))
  for (const [name, content] of Object.entries(artifacts)) {
    fs.writeFileSync(path.join(dir, name), JSON.stringify(content))
  }
  return dir
}

test('stripMetadata removes the CBOR blob', () => {
  assert.equal(stripMetadata('0x6080' + META_A), '6080')
})

test('stripMetadata keeps bytes after the blob', () => {
  assert.equal(stripMetadata('0x6080' + META_A + 'ff'.repeat(32)), '6080' + 'ff'.repeat(32))
})

test('stripMetadata leaves code without metadata unchanged', () => {
  assert.equal(stripMetadata('0x6080'), '6080')
})

test('ignores metadata-only differences', () => {
  const dir = fixture({
    'a.json': { bytecode: '0x6080' + META_A, deployedBytecode: '0x60aa' + META_A },
    'b.json': { bytecode: '0x6080' + META_B, deployedBytecode: '0x60aa' + META_B },
  })
  const a = computeHashes({ X: 'a.json' }, dir)
  const b = computeHashes({ X: 'b.json' }, dir)
  assert.deepEqual(compare(a.hashes, b.hashes), [])
})

test('detects code differences', () => {
  const dir = fixture({
    'a.json': { bytecode: '0x6080' + META_A, deployedBytecode: '0x60aa' + META_A },
    'b.json': { bytecode: '0x6080' + META_B, deployedBytecode: '0x60ab' + META_B },
  })
  const a = computeHashes({ X: 'a.json' }, dir)
  const b = computeHashes({ X: 'b.json' }, dir)
  assert.deepEqual(compare(a.hashes, b.hashes), ['X: deployedBytecode differs'])
})

test('detects differences after the metadata', () => {
  const dir = fixture({
    'a.json': { bytecode: '0x6080' + META_A + '00', deployedBytecode: '0x60aa' + META_A },
    'b.json': { bytecode: '0x6080' + META_B + '01', deployedBytecode: '0x60aa' + META_B },
  })
  const a = computeHashes({ X: 'a.json' }, dir)
  const b = computeHashes({ X: 'b.json' }, dir)
  assert.deepEqual(compare(a.hashes, b.hashes), ['X: bytecode differs'])
})

test('rejects empty bytecode', () => {
  const dir = fixture({ 'a.json': { bytecode: '0x', deployedBytecode: '0x60aa' + META_A } })
  assert.deepEqual(computeHashes({ X: 'a.json' }, dir).empty, ['X'])
})

test('fails when an artifact is missing', () => {
  const dir = fixture({})
  assert.deepEqual(computeHashes({ X: 'nope.json' }, dir).missing, ['nope.json'])
  const m = path.join(dir, 'manifest.json')
  const r = path.join(dir, 'reference.json')
  fs.writeFileSync(m, JSON.stringify({ X: 'nope.json' }))
  fs.writeFileSync(r, '{}\n')
  const res = spawnSync(process.execPath, [script, '--root', dir, '--manifest', m, '--reference', r], {
    encoding: 'utf8',
  })
  assert.equal(res.status, 1)
  assert.match(res.stderr, /nope\.json/)
})

test('write refuses to produce a partial reference', () => {
  const dir = fixture({})
  const m = path.join(dir, 'manifest.json')
  const r = path.join(dir, 'reference.json')
  fs.writeFileSync(m, JSON.stringify({ X: 'nope.json' }))
  fs.writeFileSync(r, '{"keep":true}\n')
  const res = spawnSync(process.execPath, [script, '--write', '--root', dir, '--manifest', m, '--reference', r], {
    encoding: 'utf8',
  })
  assert.equal(res.status, 1)
  assert.equal(fs.readFileSync(r, 'utf8'), '{"keep":true}\n')
})

test('runs when invoked through a symlink', () => {
  const dir = fixture({})
  const link = path.join(dir, 'link.mjs')
  fs.symlinkSync(script, link)
  const m = path.join(dir, 'manifest.json')
  const r = path.join(dir, 'reference.json')
  fs.writeFileSync(m, JSON.stringify({ X: 'nope.json' }))
  fs.writeFileSync(r, '{}\n')
  const res = spawnSync(process.execPath, [link, '--root', dir, '--manifest', m, '--reference', r], {
    encoding: 'utf8',
  })
  assert.equal(res.status, 1)
  assert.match(res.stderr, /nope\.json/)
})
