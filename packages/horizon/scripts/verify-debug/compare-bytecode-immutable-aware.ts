// scripts/compare-bytecode-immutables-aware.ts
import fs from 'node:fs'

import { ethers } from 'hardhat'

function stripCborTrailer(hex: string) {
  if (!hex || hex.length < 6) return hex
  const lenHex = hex.slice(-4)
  const len = parseInt(lenHex, 16)
  const trailerLen = len * 2 + 4 // hex chars
  if (trailerLen > 0 && trailerLen < hex.length) return hex.slice(0, hex.length - trailerLen)
  return hex
}

function maskRanges(hex: string, ranges: { start: number; length: number }[]) {
  // hex is 0x...; convert to array of bytes (2 hex chars per byte), mask with '??'
  const body = hex.startsWith('0x') ? hex.slice(2) : hex
  const bytes = body.match(/.{1,2}/g) ?? []
  for (const { start, length } of ranges) {
    for (let i = 0; i < length; i++) {
      const idx = start + i
      if (idx >= 0 && idx < bytes.length) bytes[idx] = '??'
    }
  }
  return '0x' + bytes.join('')
}

async function main() {
  const address = process.env.ADDRESS!
  const fqn = process.env.FQN // e.g. contracts/payments/GraphPayments.sol:GraphPayments

  if (!fqn || !address) {
    console.error('❌ FQN or ADDRESS is not set')
    process.exit(1)
  }

  const artifactPath = `build/contracts/${fqn.replace(/:/g, '/')}.json`
  const artifact = JSON.parse(fs.readFileSync(artifactPath, 'utf8'))

  // on-chain runtime, strip CBOR trailer
  const onchain = await ethers.provider.getCode(address)
  const onchainStripped = stripCborTrailer(onchain.toLowerCase())

  // compiled runtime from artifact (still has immutable placeholders)
  const compiled = (artifact.deployedBytecode as string).toLowerCase()
  const immRefs = artifact.immutableReferences ?? {} // { <hex slot>: [{ start, length }] }

  // Build ranges: artifact.immutableReferences lists byte offsets (not hex chars)
  const ranges: { start: number; length: number }[] = []
  for (const _ of Object.keys(immRefs)) {
    for (const ref of immRefs[_]) {
      ranges.push({ start: ref.start, length: ref.length })
    }
  }

  // mask CBOR trailer and immutable regions on BOTH sides
  const compiledStripped = stripCborTrailer(compiled)
  const maskedOnchain = maskRanges(onchainStripped, ranges)
  const maskedCompiled = maskRanges(compiledStripped, ranges)

  console.log('Masked on-chain prefix:', maskedOnchain.slice(0, 20), '…', maskedOnchain.length)
  console.log('Masked compiled pref:', maskedCompiled.slice(0, 20), '…', maskedCompiled.length)

  if (maskedOnchain === maskedCompiled) {
    console.log('✅ Runtime matches when ignoring immutables & metadata.')
  } else {
    console.error('❌ Runtime still differs after masking. Re-check solc settings / viaIR / optimizer.')
    process.exit(1)
  }
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
