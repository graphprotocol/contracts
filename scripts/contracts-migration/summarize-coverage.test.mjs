import assert from 'node:assert/strict'
import { test } from 'node:test'

import { parseLcov } from './summarize-coverage.mjs'

function da(found, hit) {
  return Array.from({ length: found }, (_, i) => `DA:${i + 1},${i < hit ? 1 : 0}`)
}

test('parses one record with an absolute CI path', () => {
  const text = [
    'SF:/home/runner/work/contracts/contracts/packages/contracts-test/contracts/rewards/RewardsManager.sol',
    ...da(200, 150),
    'end_of_record',
  ].join('\n')
  assert.deepEqual(parseLcov(text), {
    'contracts/rewards/RewardsManager.sol': { linesFound: 200, linesHit: 150, pct: 75, functionsHit: [] },
  })
})

test('keeps relative contracts paths', () => {
  const text = 'SF:contracts/upgrades/GraphProxy.sol\nDA:1,1\nend_of_record\n'
  assert.deepEqual(Object.keys(parseLcov(text)), ['contracts/upgrades/GraphProxy.sol'])
})

test('keeps records separate', () => {
  const text = [
    'SF:contracts/A.sol',
    ...da(10, 10),
    'end_of_record',
    'SF:contracts/B.sol',
    ...da(4, 1),
    'end_of_record',
  ].join('\n')
  const result = parseLcov(text)
  assert.equal(result['contracts/A.sol'].pct, 100)
  assert.equal(result['contracts/B.sol'].pct, 25)
})

test('zero lines yields null pct', () => {
  const result = parseLcov('SF:contracts/Z.sol\nend_of_record\n')
  assert.equal(result['contracts/Z.sol'].pct, null)
})

test('computes lines from DA records', () => {
  const text = 'SF:contracts/A.sol\nDA:1,3\nDA:2,0\nDA:3,1\nLF:99\nLH:99\nend_of_record\n'
  assert.deepEqual(parseLcov(text)['contracts/A.sol'], { linesFound: 3, linesHit: 2, pct: 66.67, functionsHit: [] })
})

test('merges duplicate SF records', () => {
  const text = [
    'SF:contracts/A.sol',
    'DA:1,0',
    'DA:2,1',
    'end_of_record',
    'SF:contracts/A.sol',
    'DA:1,2',
    'DA:3,0',
    'end_of_record',
  ].join('\n')
  const result = parseLcov(text)['contracts/A.sol']
  assert.equal(result.linesFound, 3)
  assert.equal(result.linesHit, 2)
})

test('lists hit functions sorted and unique', () => {
  const text = [
    'SF:contracts/A.sol',
    'FNDA:2,b',
    'FNDA:0,c',
    'FNDA:1,a',
    'end_of_record',
    'SF:contracts/A.sol',
    'FNDA:1,b',
    'end_of_record',
  ].join('\n')
  assert.deepEqual(parseLcov(text)['contracts/A.sol'].functionsHit, ['a', 'b'])
})

test('drops empty function names', () => {
  const result = parseLcov('SF:contracts/A.sol\nFNDA:1,\nend_of_record\n')
  assert.deepEqual(result['contracts/A.sol'].functionsHit, [])
})

test('file without functions has empty functionsHit', () => {
  const result = parseLcov('SF:contracts/A.sol\nDA:1,1\nend_of_record\n')
  assert.deepEqual(result['contracts/A.sol'].functionsHit, [])
})
