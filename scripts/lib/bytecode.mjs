import { createHash } from 'node:crypto'

// CBOR metadata blob: {"ipfs": <34-byte multihash>, "solc": <3-byte version>} + 2-byte length (0x0033)
const METADATA = /a264697066735822[0-9a-f]{68}64736f6c6343[0-9a-f]{6}0033/g

export function stripMetadata(bytecode) {
  return bytecode.toLowerCase().replace(/^0x/, '').replace(METADATA, '')
}

export function bytecodeHash(bytecode) {
  return createHash('sha256').update(stripMetadata(bytecode)).digest('hex')
}
