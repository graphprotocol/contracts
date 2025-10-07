import fs from 'node:fs'

import { ethers } from 'hardhat'

function stripCbor(hex: string) {
  if (!hex || hex.length < 6) return hex
  const len = parseInt(hex.slice(-4), 16)
  const trailer = len * 2 + 4
  return trailer > 0 && trailer < hex.length ? hex.slice(0, hex.length - trailer) : hex
}

function hexToBytes(hex: string) {
  const h = hex.startsWith('0x') ? hex.slice(2) : hex
  return h.match(/.{1,2}/g)?.map((b) => parseInt(b, 16)) ?? []
}
function bytesToHex(a: number[]) {
  return '0x' + a.map((b) => b.toString(16).padStart(2, '0')).join('')
}

function mask(bytes: number[], ranges: { start: number; length: number }[]) {
  const out = bytes.slice()
  for (const { start, length } of ranges) {
    for (let i = 0; i < length; i++) {
      const idx = start + i
      if (idx >= 0 && idx < out.length) out[idx] = 0xff // sentinel
    }
  }
  return out
}

function firstDiff(a: number[], b: number[]) {
  const n = Math.min(a.length, b.length)
  for (let i = 0; i < n; i++) if (a[i] !== b[i]) return i
  if (a.length !== b.length) return n
  return -1
}

async function main() {
  const ADDRESS = process.env.ADDRESS
  const FQN = process.env.FQN
  if (!FQN || !ADDRESS) {
    console.error('❌ FQN or ADDRESS is not set')
    process.exit(1)
  }

  const artifactPath = `build/contracts/${FQN.replace(/:/g, '/')}.json`
  const art = JSON.parse(fs.readFileSync(artifactPath, 'utf8'))

  const on = stripCbor((await ethers.provider.getCode(ADDRESS)).toLowerCase())
  const comp = stripCbor((art.deployedBytecode as string).toLowerCase())

  // Gather immutable ranges from artifact
  const immRefs = art.immutableReferences ?? {}
  const ranges: { start: number; length: number }[] = []
  for (const k of Object.keys(immRefs)) for (const r of immRefs[k]) ranges.push({ start: r.start, length: r.length })

  console.log('immutable ranges:', ranges)

  const onBytes = hexToBytes(on)
  const compBytes = hexToBytes(comp)

  // Mask immutables on both sides
  const onMasked = mask(onBytes, ranges)
  const compMasked = mask(compBytes, ranges)

  const i = firstDiff(onMasked, compMasked)
  if (i === -1) {
    console.log('✅ Runtime matches after masking immutables & stripping metadata.')
    return
  }

  const lo = Math.max(0, i - 32),
    hi = Math.min(onMasked.length, i + 32)
  console.log('❌ First diff at byte offset:', i)
  console.log('on-chain   :', bytesToHex(onBytes.slice(lo, hi)))
  console.log('compiled   :', bytesToHex(compBytes.slice(lo, hi)))
  console.log('on-masked  :', bytesToHex(onMasked.slice(lo, hi)))
  console.log('comp-masked:', bytesToHex(compMasked.slice(lo, hi)))
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
