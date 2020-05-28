import {
  defaultAbiCoder as abi,
  keccak256,
  hexlify,
  SigningKey,
  solidityKeccak256,
  toUtf8Bytes,
} from 'ethers/utils'

export interface Receipt {
  requestCID: string
  responseCID: string
  subgraphID: string
}

function encodeReceipt(receipt: Receipt) {
  // ABI encoded
  return abi.encode(
    ['bytes32', 'bytes32', 'bytes32'],
    [receipt.requestCID, receipt.responseCID, receipt.subgraphID],
  )
}

function createReceiptHash(encodedReceipt: string) {
  const receiptTypeHash = keccak256(
    toUtf8Bytes('Receipt(bytes32 requestCID,bytes32 responseCID,bytes32 subgraphID)'),
  )

  // ABI encoded
  return keccak256(abi.encode(['bytes32', 'bytes'], [receiptTypeHash, encodedReceipt]))
}

function createDomainSeparatorHash(contractAddress: string, chainID: string | number) {
  const domainTypeHash = keccak256(
    toUtf8Bytes(
      'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)',
    ),
  )
  const domainNameHash = keccak256(toUtf8Bytes('Graph Protocol'))
  const domainVersionHash = keccak256(toUtf8Bytes('0'))
  const domainSalt = '0xa070ffb1cd7409649bf77822cce74495468e06dbfaef09556838bf188679b9c2'

  // ABI encoded
  return keccak256(
    abi.encode(
      ['bytes32', 'bytes32', 'bytes32', 'uint256', 'address', 'bytes32'],
      [domainTypeHash, domainNameHash, domainVersionHash, chainID, contractAddress, domainSalt],
    ),
  )
}

function createMessage(domainSeparatorHash: string, receiptHash: string) {
  return '0x1901' + domainSeparatorHash.substring(2) + receiptHash.substring(2)
}

function createAttestation(encodedReceipt: string, messageSig: string) {
  return (
    '0x' +
    encodedReceipt.substring(2) + // Receipt
    messageSig.substring(2) // Signature
  )
}

function createDisputeID(receipt: Receipt, indexer: string) {
  return solidityKeccak256(
    ['bytes32', 'bytes32', 'bytes32', 'address'],
    [receipt.requestCID, receipt.responseCID, receipt.subgraphID, indexer],
  )
}

export default async function createDispute(
  receipt: Receipt,
  contractAddress: string,
  signer: string,
  indexer: string,
  chainID: string | number,
) {
  // Receipt
  const encodedReceipt = encodeReceipt(receipt)

  // Receipt signing to create the attestation
  const message = createMessage(
    createDomainSeparatorHash(contractAddress, chainID),
    createReceiptHash(encodedReceipt),
  )

  const signingKey = new SigningKey(signer)
  const messageHash = keccak256(message)
  const signature = signingKey.signDigest(messageHash)
  const messageSig =
    '0x' + hexlify(signature.v).substring(2) + signature.r.substring(2) + signature.s.substring(2)

  // Attestation bytes: 96 (receipt) + 65 (signature) = 161
  const attestation = createAttestation(encodedReceipt, messageSig)

  return {
    id: createDisputeID(receipt, indexer),
    signer,
    attestation,
    receipt,
    message,
    messageSig,
  }
}
