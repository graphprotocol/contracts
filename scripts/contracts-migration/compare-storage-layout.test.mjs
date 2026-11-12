import assert from 'node:assert/strict'
import { test } from 'node:test'

import { compareLayouts } from './compare-storage-layout.mjs'

const uint = { encoding: 'inplace', label: 'uint256', numberOfBytes: '32' }
const addr = { encoding: 'inplace', label: 'address', numberOfBytes: '20' }

const entry = (label, slot, type, extra = {}) => ({
  astId: 1,
  contract: 'contracts/A.sol:A',
  label,
  offset: 0,
  slot: String(slot),
  type,
  ...extra,
})

const struct = (members) => ({
  encoding: 'inplace',
  label: 'struct A.S',
  numberOfBytes: String(32 * members.length),
  members,
})

const base = () => ({
  storage: [entry('a', 0, 't_uint256'), entry('b', 1, 't_address')],
  types: { t_uint256: uint, t_address: addr },
})

test('identical layouts give no differences', () => {
  assert.deepEqual(compareLayouts(base(), base()), [])
})

test('a changed slot is reported with the label', () => {
  const after = base()
  after.storage[1].slot = '2'
  const diffs = compareLayouts(base(), after)
  assert.equal(diffs.length, 1)
  assert.match(diffs[0], /\bb\b/)
})

test('a changed offset is reported with the label', () => {
  const after = base()
  after.storage[1].offset = 12
  const diffs = compareLayouts(base(), after)
  assert.equal(diffs.length, 1)
  assert.match(diffs[0], /\bb\b/)
})

test('astId, contract and type ids are ignored', () => {
  const after = {
    storage: [
      entry('a', 0, 't_uint256', { astId: 99, contract: 'contracts/B.sol:B' }),
      entry('b', 1, 't_contract(IRewardsIssuer)1234', { astId: 100 }),
    ],
    types: { t_uint256: uint, 't_contract(IRewardsIssuer)1234': addr },
  }
  assert.deepEqual(compareLayouts(base(), after), [])
})

const withStruct = (members, viaMapping) => {
  const s = struct(members)
  const types = { t_uint256: uint, t_address: addr, 't_struct(S)1': s }
  if (viaMapping) {
    types['t_mapping(t_uint256,t_struct(S)1)'] = {
      encoding: 'mapping',
      label: 'mapping(uint256 => struct A.S)',
      numberOfBytes: '32',
      key: 't_uint256',
      value: 't_struct(S)1',
    }
  }
  return {
    storage: [entry('s', 0, viaMapping ? 't_mapping(t_uint256,t_struct(S)1)' : 't_struct(S)1')],
    types,
  }
}

const members = () => [entry('x', 0, 't_uint256'), entry('y', 1, 't_address')]
const swapped = () => [entry('y', 0, 't_address'), entry('x', 1, 't_uint256')]

test('a struct member moved inside a struct is reported', () => {
  assert.notDeepEqual(compareLayouts(withStruct(members(), false), withStruct(swapped(), false)), [])
})

test('a struct member moved inside a mapped struct is reported', () => {
  assert.notDeepEqual(compareLayouts(withStruct(members(), true), withStruct(swapped(), true)), [])
})

test('variables with the same label are compared separately', () => {
  const layout = () => ({
    storage: [entry('__gap', 0, 't_uint256'), entry('x', 1, 't_uint256'), entry('__gap', 2, 't_uint256')],
    types: { t_uint256: uint },
  })
  const after = layout()
  after.storage[2].slot = '3'
  const diffs = compareLayouts(layout(), after)
  assert.equal(diffs.length, 1)
  assert.match(diffs[0], /__gap/)
})

test('a variable added at the end is reported', () => {
  const after = base()
  after.storage.push(entry('c', 2, 't_uint256'))
  const diffs = compareLayouts(base(), after)
  assert.equal(diffs.length, 1)
  assert.match(diffs[0], /\bc\b/)
})
