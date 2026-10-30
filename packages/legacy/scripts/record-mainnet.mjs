#!/usr/bin/env node
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

import { compileBundle, normalizeRuntime, runtimeHash } from './lib.mjs'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const EIP1967_IMPLEMENTATION_SLOT = '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc'

function fail(message) {
  console.error(message)
  process.exit(1)
}

const url = process.env.MAINNET_RPC_URL
if (!url) fail('MAINNET_RPC_URL is required')

// Errors from fetch can carry the URL, so they are replaced rather than rethrown
async function rpc(method, params) {
  let response
  try {
    response = await fetch(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }),
    })
  } catch {
    throw new Error(`${method}: request failed`)
  }
  if (!response.ok) throw new Error(`${method}: HTTP ${response.status}`)
  const { result, error } = await response.json()
  if (error) throw new Error(`${method}: RPC error ${error.code}`)
  return result
}

function extensionImplSlot(storageLayout) {
  const entries = storageLayout.storage.filter((entry) => entry.label === 'extensionImpl')
  if (entries.length !== 1) fail(`expected one extensionImpl in L1Staking layout, found ${entries.length}`)
  // The check below reads the low 20 bytes, which is only this variable at offset 0
  if (entries[0].offset !== 0) fail(`extensionImpl is at offset ${entries[0].offset}, expected 0`)
  return `0x${BigInt(entries[0].slot).toString(16)}`
}

const targets = JSON.parse(fs.readFileSync(path.join(root, 'targets.json'), 'utf8'))
const bundles = Object.fromEntries(
  Object.keys(targets).map((name) => [name, compileBundle(path.join(root, 'verified', name))]),
)

const { number } = await rpc('eth_getBlockByNumber', ['finalized', false])
const block = Number(number)

for (const [name, { implementation, proxy }] of Object.entries(targets)) {
  if (!proxy) continue
  const word = await rpc('eth_getStorageAt', [proxy, EIP1967_IMPLEMENTATION_SLOT, number])
  if (BigInt(word) !== BigInt(implementation)) fail(`${name}: proxy points at ${word}, not ${implementation}`)
  console.log(`${name}: proxy implementation slot matches ${implementation}`)
}

const slot = extensionImplSlot(bundles.L1Staking.storageLayout)
const word = await rpc('eth_getStorageAt', [targets.L1Staking.proxy, slot, number])
const extensionImpl = `0x${word.slice(-40)}`
if (extensionImpl.toLowerCase() !== targets.StakingExtension.implementation.toLowerCase()) {
  fail(`StakingExtension: L1Staking extensionImpl is ${extensionImpl}, not ${targets.StakingExtension.implementation}`)
}
console.log(`StakingExtension: L1Staking extensionImpl (slot ${BigInt(slot)}) matches ${extensionImpl}`)

const contracts = {}
for (const [name, { implementation, proxy }] of Object.entries(targets)) {
  const code = await rpc('eth_getCode', [implementation, number])
  if (code === '0x') fail(`${name}: no code at ${implementation}`)
  contracts[name] = { implementation, proxy, runtimeHash: runtimeHash(normalizeRuntime(code, bundles[name].ranges)) }
}

fs.writeFileSync(path.join(root, 'mainnet.json'), JSON.stringify({ block, contracts }, null, 2) + '\n')
console.log(`recorded ${Object.keys(contracts).length} contracts at block ${block}`)
