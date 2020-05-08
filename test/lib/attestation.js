const Account = require('eth-lib/lib/account')

function createReceipt(subgraphId) {
  const attestation = {
    requestCID: web3.utils.randomHex(32),
    responseCID: web3.utils.randomHex(32),
    subgraphId: subgraphId,
  }

  // ABI encoded
  return web3.eth.abi.encodeParameters(
    ['bytes32', 'bytes32', 'bytes32'],
    [attestation.requestCID, attestation.responseCID, attestation.subgraphId],
  )
}

function createReceiptHash(attestation) {
  const attestationTypeHash = web3.utils.sha3(
    'Attestation(bytes32 requestCID,bytes32 responseCID,bytes32 subgraphID)',
  )

  // ABI encoded
  return web3.utils.sha3(
    web3.eth.abi.encodeParameters(['bytes32', 'bytes'], [attestationTypeHash, attestation]),
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

function createMessage(domainSeparatorHash, attestationHash) {
  return '0x1901' + domainSeparatorHash.substring(2) + attestationHash.substring(2)
}

function createAttestation(receipt, messageSig) {
  return (
    '0x' +
    receipt.substring(2) + // Attestation
    messageSig.substring(2) // Signature
  ) // receipt + signature = attestation in EIP712 format
}

async function createDisputePayload(subgraphId, contractAddress, signer) {
  // Attestation
  const receipt = createReceipt(subgraphId)

  // Attestation signing wrapped in EIP721 format
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
