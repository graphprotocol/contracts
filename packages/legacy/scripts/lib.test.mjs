import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { test } from 'node:test'
import { fileURLToPath } from 'node:url'

import { checkSources, compareAddresses, compileBundle, normalizeRuntime, runtimeHash, runtimeRanges } from './lib.mjs'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const BRIDGE_ESCROW_DIR = path.join(root, 'verified/BridgeEscrow')

const readMainnet = () => JSON.parse(fs.readFileSync(path.join(root, 'mainnet.json'), 'utf8')).contracts
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

test('normalizeRuntime zeroes ranges and removes metadata', () => {
  // 4 code bytes, then a 2-byte CBOR blob and its 2-byte length
  assert.equal(normalizeRuntime('0xAABBCCDD' + 'eeff' + '0002', [{ start: 1, length: 2 }]), 'aa0000dd')
})

test('runtimeRanges reads immutable and link references', () => {
  const ranges = runtimeRanges({
    immutableReferences: { 1: [{ start: 3, length: 32 }] },
    linkReferences: { 'a.sol': { Lib: [{ start: 40, length: 20 }] } },
  })
  assert.deepEqual(ranges, [
    { start: 3, length: 32 },
    { start: 40, length: 20 },
  ])
})

test('verified BridgeEscrow matches mainnet.json', () => {
  const { object, ranges } = compileBundle(BRIDGE_ESCROW_DIR)
  assert.equal(runtimeHash(normalizeRuntime(object, ranges)), readMainnet().BridgeEscrow.runtimeHash)
})

test('a code change no longer matches mainnet.json', (t) => {
  const dir = copyBundle(t)
  editTarget(dir, (src) =>
    src.replace(
      /contract BridgeEscrow\b[^{]*\{/,
      (m) => `${m} function inserted() external pure returns (uint256) { return 1; }`,
    ),
  )
  const { object, ranges } = compileBundle(dir)
  assert.notEqual(runtimeHash(normalizeRuntime(object, ranges)), readMainnet().BridgeEscrow.runtimeHash)
})

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

test('compareAddresses reports mismatched addresses', () => {
  const targets = {
    A: { implementation: '0xAbC', proxy: '0xDeF' },
    B: { implementation: '0x123', proxy: null },
  }
  assert.deepEqual(
    compareAddresses(targets, {
      A: { implementation: '0xabc', proxy: '0xdef', runtimeHash: 'x' },
      B: { implementation: '0x123', proxy: null, runtimeHash: 'y' },
    }),
    [],
  )
  assert.deepEqual(
    compareAddresses(targets, {
      A: { implementation: '0xbad', proxy: '0xDeF' },
      B: { implementation: '0x123', proxy: '0xbad' },
    }),
    [
      'A: implementation is 0xAbC in targets.json, 0xbad in mainnet.json',
      'B: proxy is null in targets.json, 0xbad in mainnet.json',
    ],
  )
})

test('compareAddresses skips contracts missing from either file', () => {
  assert.deepEqual(compareAddresses({ A: { implementation: '0x1', proxy: null } }, {}), [])
})
