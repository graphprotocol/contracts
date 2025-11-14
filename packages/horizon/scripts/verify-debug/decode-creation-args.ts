// scripts/decode-creation-args.ts
import fs from 'node:fs'

import { ethers } from 'hardhat'

function stripCborTrailer(hex: string) {
  // Remove trailing CBOR metadata based on the last 2 bytes length
  if (!hex || hex.length < 6) return hex
  const lenHex = hex.slice(-4)
  const len = parseInt(lenHex, 16)
  const trailerLen = len * 2 + 4 // hex chars
  if (trailerLen > 0 && trailerLen < hex.length) return hex.slice(0, hex.length - trailerLen)
  return hex
}

async function main() {
  const FQN = process.env.FQN // e.g. "contracts/payments/GraphPayments.sol:GraphPayments"
  const TX = process.env.TX // deployment tx hash

  if (!FQN || !TX) {
    console.error('❌ FQN or TX is not set')
    process.exit(1)
  }

  const artifactPath = `build/contracts/${FQN.replace(/:/g, '/')}.json`
  const artifact = JSON.parse(fs.readFileSync(artifactPath, 'utf8'))

  const tx = await ethers.provider.getTransaction(TX)
  if (!tx?.data) throw new Error('Cannot fetch tx.data; check TX hash / network')

  const txData = tx.data.toLowerCase()
  let creation = (artifact.bytecode as string).toLowerCase()
  if (creation.startsWith('0x') === false) creation = '0x' + creation

  // Try exact prefix match first
  let prefix = creation
  if (!txData.startsWith(prefix)) {
    // Try stripping CBOR trailers from both sides just in case
    prefix = stripCborTrailer(prefix)
    const txNoCbor = stripCborTrailer(txData)
    if (txNoCbor.startsWith(prefix)) {
      // use tx with its trailer stripped as well
      const argsData = '0x' + txNoCbor.slice(prefix.length)
      await decode(argsData, artifact)
      return
    }
    // Fallback: find the longest prefix that matches (robust against tiny metadata diffs)
    let i = Math.min(prefix.length, txData.length)
    while (i > 2 && !txData.startsWith(prefix.slice(0, i))) i -= 2
    if (i <= 2) {
      throw new Error('Creation bytecode prefix not found in tx.data. Check solc settings.')
    }
    const argsData = '0x' + txData.slice(i)
    await decode(argsData, artifact)
    return
  }

  const argsData = '0x' + txData.slice(prefix.length)
  await decode(argsData, artifact)
}

interface AbiInput {
  type: string
  name?: string
}

interface AbiConstructor {
  type: string
  inputs?: AbiInput[]
}

interface Artifact {
  abi: AbiConstructor[]
  bytecode: string
}

async function decode(argsData: string, artifact: Artifact) {
  const ctor = artifact.abi.find((x) => x.type === 'constructor')
  const types = ctor?.inputs?.map((i) => i.type) ?? []
  if (types.length === 0) {
    if (argsData === '0x' || argsData.length <= 2) {
      console.log('Constructor has no params. Args: []')
      return
    } else {
      console.warn('No constructor inputs in ABI, but args data present. Types unknown.')
      console.log('Raw argsData:', argsData)
      return
    }
  }

  const coder = ethers.AbiCoder.defaultAbiCoder()
  const decoded = coder.decode(types, argsData)
  // Pretty-print as JSON array so you can reuse directly
  const printable = decoded.map((v) => (typeof v === 'bigint' ? v.toString() : v))
  console.log('Constructor types:', types)
  console.log('Decoded args JSON:', JSON.stringify(printable))
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
