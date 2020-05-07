const Account = require('eth-lib/lib/account')

function createAttestation(subgraphId) {
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

function createAttestationHash(attestation) {
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

function createPayload(attestation, messageSig) {
  return (
    '0x' +
    attestation.substring(2) + // Attestation
    messageSig.substring(2) // Signature
  ) // raw attestation data + signed attestation in EIP712 format
}

async function createDisputePayload(subgraphId, contractAddress, signer) {
  // Attestation
  const attestation = createAttestation(subgraphId)

  // Attestation signing wrapped in EIP721 format
  const message = createMessage(
    createDomainSeparatorHash(contractAddress),
    createAttestationHash(attestation),
  )
  const messageHash = web3.utils.sha3(message)
  const messageSig = Account.sign(messageHash, signer)

  // Payload bytes: 96 + 65 = 161
  const payload = createPayload(attestation, messageSig)

  return {
    signer,
    subgraphId,
    attestation,
    message,
    messageHash,
    messageSig,
    payload,
  }
}

module.exports = {
  createDisputePayload: createDisputePayload,
}
