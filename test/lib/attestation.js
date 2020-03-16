// helpers
const helpers = require('./testHelpers')

function createAttestation() {
  const attestation = {
    requestCID: {
      hash: web3.utils.randomHex(32),
      hashFunction: '0x1220',
    },
    responseCID: {
      hash: web3.utils.randomHex(32),
      hashFunction: '0x1220',
    },
    gasUsed: 123000, // Math.floor(Math.random() * 100000) + 100000,
    responseBytes: 4500, // Math.floor(Math.random() * 3000) + 1000
  }

  // ABI encoded
  return web3.eth.abi.encodeParameters(
    ['bytes32', 'uint16', 'bytes32', 'uint16', 'uint256', 'uint256'],
    [
      attestation.requestCID.hash,
      attestation.requestCID.hashFunction,
      attestation.responseCID.hash,
      attestation.responseCID.hashFunction,
      attestation.gasUsed,
      attestation.responseBytes,
    ],
  )
}

function createAttestationHash(attestation) {
  const attestationTypeHash = web3.utils.sha3(
    'Attestation(IpfsHash requestCID,IpfsHash responseCID,uint256 gasUsed,uint256 responseNumBytes)IpfsHash(bytes32 hash,uint16 hashFunction)',
  )

  // ABI encoded
  return web3.utils.sha3(
    web3.eth.abi.encodeParameters(
      ['bytes32', 'bytes'],
      [attestationTypeHash, attestation],
    ),
  )
}

function createDomainSeparatorHash(contractAddress) {
  const chainId = 1
  const domainTypeHash = web3.utils.sha3(
    'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)',
  )
  const domainNameHash = web3.utils.sha3('Graph Protocol')
  const domainVersionHash = web3.utils.sha3('0.1')

  // ABI encoded
  return web3.utils.sha3(
    web3.eth.abi.encodeParameters(
      ['bytes32', 'bytes32', 'bytes32', 'uint256', 'address'],
      [
        domainTypeHash,
        domainNameHash,
        domainVersionHash,
        chainId,
        contractAddress,
      ],
    ),
  )
}

function createMessage(domainSeparatorHash, attestationHash) {
  return domainSeparatorHash + attestationHash.substring(2)
}

function createPayload(subgraphId, attestation, messageSig) {
  return (
    '0x' +
    subgraphId.substring(2) + // Subgraph ID without `0x` (32 bytes)
    attestation.substring(2) + // Attestation
    messageSig.substring(2)
  ) // IEP712 : domain separator + signed attestation
}

async function createDisputePayload(subgraphId, contractAddress, signer) {
  // Attestation
  const attestation = createAttestation()
  const attestationHash = createAttestationHash(attestation)

  // Domain (EIP-712)
  const domainSeparatorHash = createDomainSeparatorHash(contractAddress)

  // Message
  const message = createMessage(domainSeparatorHash, attestationHash)
  const messageSig = helpers.fixSignature(await web3.eth.sign(message, signer))
  // WARN: sign() prepends the "\x19Ethereum Signed Message:\n64" we could
  // raw sign to use the EIP-191 encoding pad, EIP-712 version 1 -> 0x1901

  // required bytes: 32 + 257 = 289
  const payload = createPayload(subgraphId, attestation, messageSig)

  return {
    signer,

    // domain
    domainSeparatorHash: domainSeparatorHash,

    // subgraphId
    subgraphId,

    // attestation
    attestation,
    attestationHash,

    // message
    message,
    messageHash: helpers.toEthSignedMessageHash(message),
    messageSig,

    // payload
    payload,
  }
}

module.exports = {
  createDisputePayload: createDisputePayload,
}
