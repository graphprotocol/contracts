import assert from 'node:assert/strict'
import { test } from 'node:test'

import { parseLcov } from './summarize-coverage.mjs'

test('parses one record with an absolute CI path', () => {
  const text = [
    'SF:/home/runner/work/contracts/contracts/packages/contracts-test/contracts/rewards/RewardsManager.sol',
    'LF:200',
    'LH:150',
    'end_of_record',
  ].join('\n')
  assert.deepEqual(parseLcov(text), {
    'contracts/rewards/RewardsManager.sol': { linesFound: 200, linesHit: 150, pct: 75 },
  })
})

test('keeps relative contracts paths', () => {
  const text = 'SF:contracts/upgrades/GraphProxy.sol\nLF:1\nLH:1\nend_of_record\n'
  assert.deepEqual(Object.keys(parseLcov(text)), ['contracts/upgrades/GraphProxy.sol'])
})

test('keeps records separate', () => {
  const text = [
    'SF:contracts/A.sol',
    'LF:10',
    'LH:10',
    'end_of_record',
    'SF:contracts/B.sol',
    'LF:4',
    'LH:1',
    'end_of_record',
  ].join('\n')
  const result = parseLcov(text)
  assert.equal(result['contracts/A.sol'].pct, 100)
  assert.equal(result['contracts/B.sol'].pct, 25)
})

test('zero lines yields null pct', () => {
  const result = parseLcov('SF:contracts/Z.sol\nLF:0\nLH:0\nend_of_record\n')
  assert.equal(result['contracts/Z.sol'].pct, null)
})
