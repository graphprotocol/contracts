import assert from 'node:assert/strict'
import { test } from 'node:test'

import { compareCoverage } from './compare-coverage.mjs'

const file = (linesFound, linesHit, functionsHit) => ({
  linesFound,
  linesHit,
  pct: linesFound === 0 ? null : Math.round((linesHit / linesFound) * 10000) / 100,
  functionsHit,
})

test('passes when every baseline function is still hit', () => {
  const baseline = { 'contracts/A.sol': file(10, 10, ['a', 'b']) }
  const current = { 'contracts/A.sol': file(10, 10, ['b', 'a', 'c']) }
  assert.deepEqual(compareCoverage(baseline, current, ['contracts/A.sol']), { regressions: [], belowLines: [] })
})

test('a baseline function missing from current is a regression', () => {
  const baseline = { 'contracts/A.sol': file(10, 10, ['a', 'b']) }
  const current = { 'contracts/A.sol': file(10, 10, ['a']) }
  const { regressions } = compareCoverage(baseline, current, ['contracts/A.sol'])
  assert.equal(regressions.length, 1)
  assert.match(regressions[0], /contracts\/A\.sol/)
  assert.match(regressions[0], /\bb\b/)
})

test('strips a Contract. prefix before comparing', () => {
  const baseline = { 'contracts/A.sol': file(10, 10, ['a']) }
  const current = { 'contracts/A.sol': file(10, 10, ['A.a']) }
  assert.deepEqual(compareCoverage(baseline, current, ['contracts/A.sol']).regressions, [])
})

test('a named file absent from current is a regression', () => {
  const baseline = { 'contracts/A.sol': file(10, 10, ['a']) }
  const { regressions } = compareCoverage(baseline, {}, ['contracts/A.sol'])
  assert.equal(regressions.length, 1)
  assert.match(regressions[0], /contracts\/A\.sol/)
})

test('a file absent from current is fine when its baseline has no lines', () => {
  const baseline = { 'contracts/I.sol': file(0, 0, []) }
  assert.deepEqual(compareCoverage(baseline, {}, ['contracts/I.sol']), { regressions: [], belowLines: [] })
})

test('a file absent from the baseline throws', () => {
  assert.throws(() => compareCoverage({}, {}, ['contracts/X.sol']), /contracts\/X\.sol/)
})

test('a lower line percentage is reported but is not a regression', () => {
  const baseline = { 'contracts/A.sol': file(10, 10, ['a']) }
  const current = { 'contracts/A.sol': file(10, 8, ['a']) }
  const result = compareCoverage(baseline, current, ['contracts/A.sol'])
  assert.deepEqual(result.regressions, [])
  assert.equal(result.belowLines.length, 1)
  assert.match(result.belowLines[0], /contracts\/A\.sol/)
})

test('a baseline function matches a forge overload suffix', () => {
  const baseline = { 'contracts/G.sol': file(10, 10, ['outboundTransfer']) }
  const current = { 'contracts/G.sol': file(10, 10, ['L2GraphTokenGateway.outboundTransfer.0']) }
  assert.deepEqual(compareCoverage(baseline, current, ['contracts/G.sol']).regressions, [])
})

test('a baseline function is a regression when no overload is hit', () => {
  const baseline = { 'contracts/G.sol': file(10, 10, ['outboundTransfer']) }
  const current = { 'contracts/G.sol': file(10, 10, ['L2GraphTokenGateway.finalizeInboundTransfer.1']) }
  assert.equal(compareCoverage(baseline, current, ['contracts/G.sol']).regressions.length, 1)
})
