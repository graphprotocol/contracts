import { hexlify, hexZeroPad, RLP } from 'ethers/lib/utils'

const BLOCK_HEADER_FIELDS = [
  'parentHash',
  'sha3Uncles',
  'miner',
  'stateRoot',
  'transactionsRoot',
  'receiptsRoot',
  'logsBloom',
  'difficulty',
  'number',
  'gasLimit',
  'gasUsed',
  'timestamp',
  'extraData',
  'mixHash',
  'nonce',
  'baseFeePerGas',
]

// Expected to come from an eth_getBlockByNumber call
interface GetBlockResponse {
  parentHash: string
  sha3Uncles: string
  miner: string
  stateRoot: string
  transactionsRoot: string
  receiptsRoot: string
  logsBloom: string
  difficulty: string
  number: string
  gasLimit: string
  gasUsed: string
  timestamp: string
  extraData: string
  mixHash: string
  nonce: string
  baseFeePerGas: string
}

interface SlotProof {
  key: string
  proof: Array<string>
  value: string
}
interface GetProofResponse {
  accountProof: Array<string>
  address: string
  balance: string
  codeHash: string
  nonce: string
  storageHash: string
  storageProof: Array<SlotProof>
}

const toNonzeroEvenLengthHex = (hex: string): string => {
  if (hex == '0x0') {
    return '0x'
  } else if (hex.length % 2 == 0) {
    return hex
  } else {
    return hexZeroPad(hex, Math.floor(hex.length / 2))
  }
}

export const getBlockHeaderRLP = (block: GetBlockResponse): string => {
  const header = BLOCK_HEADER_FIELDS.map((field) => hexlify(toNonzeroEvenLengthHex(block[field])))
  return RLP.encode(header)
}

export const encodeMPTStorageProofRLP = (proof: GetProofResponse): string => {
  if (proof.storageProof.length !== 1) {
    throw new Error('Expected exactly one storage slot proof')
  }
  const accountProof = proof.accountProof.map((node) => RLP.decode(hexlify(node)))
  console.log('Account proof:')
  console.log(accountProof)
  const storageProof = proof.storageProof[0].proof.map((node) => RLP.decode(hexlify(node)))
  console.log('Storage proof:')
  console.log(storageProof)
  return RLP.encode([accountProof, storageProof])
}
