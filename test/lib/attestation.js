const Account = require('eth-lib/lib/account')

function createReceipt(subgraphId) {
  const receipt = {
    requestCID: web3.utils.randomHex(32),
    responseCID: web3.utils.randomHex(32),
    subgraphId: subgraphId,
  }

  // ABI encoded
  return web3.eth.abi.encodeParameters(
    ['bytes32', 'bytes32', 'bytes32'],
    [receipt.requestCID, receipt.responseCID, receipt.subgraphId],
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

function createAttestation(receipt, messageSig) {
  return (
    '0x' +
    receipt.substring(2) + // Receipt
    messageSig.substring(2) // Signature
  )
}

async function createDisputePayload(subgraphId, contractAddress, signer) {
  // Receipt
  const receipt = createReceipt(subgraphId)

  // Receipt signing to create the attestation
  const message = createMessage(
    createDomainSeparatorHash(contractAddress),
    createReceiptHash(receipt),
  )
  const messageHash = web3.utils.sha3(message)
  const messageSig = Account.sign(messageHash, signer)

  // Attestation bytes: 96 (receipt) + 65 (signature) = 161
  const attestation = createAttestation(receipt, messageSig)

  return {
    signer,
    subgraphId,
    attestation,
    message,
    messageHash,
    messageSig,
  }
}

module.exports = {
  createDisputePayload: createDisputePayload,
}
