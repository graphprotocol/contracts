const ethers = require('ethers')

function encodeReceipt(receipt) {
  // ABI encoded
  return web3.eth.abi.encodeParameters(
    ['bytes32', 'bytes32', 'bytes32'],
    [receipt.requestCID, receipt.responseCID, receipt.subgraphID],
  )
}

function createReceiptHash(receipt) {
  const receiptTypeHash = web3.utils.sha3(
    'Receipt(bytes32 requestCID,bytes32 responseCID,bytes32 subgraphID)',
  )

  // ABI encoded
  return web3.utils.sha3(
    web3.eth.abi.encodeParameters(['bytes32', 'bytes'], [receiptTypeHash, receipt]),
  )
}

function createDomainSeparatorHash(contractAddress) {
  const chainId = 1
  const domainTypeHash = web3.utils.sha3(
    'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)',
  )
  const domainNameHash = web3.utils.sha3('Graph Protocol')
  const domainVersionHash = web3.utils.sha3('0')
  const domainSalt = '0xa070ffb1cd7409649bf77822cce74495468e06dbfaef09556838bf188679b9c2'

  // ABI encoded
  return web3.utils.sha3(
    web3.eth.abi.encodeParameters(
      ['bytes32', 'bytes32', 'bytes32', 'uint256', 'address', 'bytes32'],
      [domainTypeHash, domainNameHash, domainVersionHash, chainId, contractAddress, domainSalt],
    ),
  )
}

function createMessage(domainSeparatorHash, receiptHash) {
  return '0x1901' + domainSeparatorHash.substring(2) + receiptHash.substring(2)
}

function createAttestation(encodedReceipt, messageSig) {
  return (
    '0x' +
    encodedReceipt.substring(2) + // Receipt
    messageSig.substring(2) // Signature
  )
}

function createDisputeID(receipt, indexer) {
  return ethers.utils.solidityKeccak256(
    ['bytes32', 'bytes32', 'bytes32', 'address'],
    [receipt.requestCID, receipt.responseCID, receipt.subgraphID, indexer],
  )
}

async function createDispute(receipt, contractAddress, signer, indexer) {
  // Receipt
  const encodedReceipt = encodeReceipt(receipt)

  // Receipt signing to create the attestation
  const message = createMessage(
    createDomainSeparatorHash(contractAddress),
    createReceiptHash(encodedReceipt),
  )

  const signingKey = new ethers.utils.SigningKey(signer)
  const messageHash = ethers.utils.keccak256(message)
  const signature = signingKey.signDigest(messageHash)
  const messageSig =
    '0x' +
    ethers.utils.hexlify(signature.v).substring(2) +
    signature.r.substring(2) +
    signature.s.substring(2)

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

module.exports = {
  createDispute: createDispute,
}
