import { BytesLike, ethers, id, Signature, Wallet } from 'ethers'

import type { RAV, Receipt } from './types'

export const EIP712_DOMAIN_NAME = 'GraphTallyCollector'
export const EIP712_DOMAIN_VERSION = '1'

export const EIP712_RAV_PROOF_TYPEHASH = id(
  'ReceiptAggregateVoucher(bytes32 collectionId,address payer,address serviceProvider,address dataService,uint64 timestampNs,uint128 valueAggregate,bytes metadata)',
)
export const EIP712_RAV_PROOF_TYPES = {
  ReceiptAggregateVoucher: [
    { name: 'collectionId', type: 'bytes32' },
    { name: 'payer', type: 'address' },
    { name: 'serviceProvider', type: 'address' },
    { name: 'dataService', type: 'address' },
    { name: 'timestampNs', type: 'uint64' },
    { name: 'valueAggregate', type: 'uint128' },
    { name: 'metadata', type: 'bytes' },
  ],
}

export const EIP712_RECEIPT_PROOF_TYPEHASH = id(
  'Receipt(bytes32 collection_id,address payer,address data_service,address service_provider,uint64 timestamp_ns,uint64 nonce,uint128 value)',
)

export const EIP712_RECEIPT_PROOF_TYPES = {
  Receipt: [
    { name: 'collection_id', type: 'bytes32' },
    { name: 'payer', type: 'address' },
    { name: 'data_service', type: 'address' },
    { name: 'service_provider', type: 'address' },
    { name: 'timestamp_ns', type: 'uint64' },
    { name: 'nonce', type: 'uint64' },
    { name: 'value', type: 'uint128' },
  ],
}

/**
 * Generates a signed RAV
 * @param allocationId The allocation ID
 * @param payer The payer
 * @param serviceProvider The service provider
 * @param dataService The data service
 * @param timestampNs The timestamp in nanoseconds
 * @param valueAggregate The value aggregate
 * @param metadata The metadata
 * @param signerPrivateKey The private key of the signer
 * @param graphTallyCollectorAddress The address of the Graph Tally Collector contract
 * @param chainId The chain ID
 * @returns The encoded signed RAV calldata
 */
export async function generateSignedRAV(
  allocationId: string,
  payer: string,
  serviceProvider: string,
  dataService: string,
  timestampNs: number,
  valueAggregate: bigint,
  metadata: BytesLike,
  signerPrivateKey: string,
  graphTallyCollectorAddress: string,
  chainId: number,
): Promise<{ rav: RAV; signature: string }> {
  // Create the domain for the EIP712 signature
  const domain = {
    name: EIP712_DOMAIN_NAME,
    version: EIP712_DOMAIN_VERSION,
    chainId,
    verifyingContract: graphTallyCollectorAddress,
  }

  // Create the RAV data
  const ravData = {
    collectionId: ethers.zeroPadValue(allocationId, 32),
    payer: payer,
    serviceProvider: serviceProvider,
    dataService: dataService,
    timestampNs: timestampNs,
    valueAggregate: valueAggregate,
    metadata: metadata,
  }

  // Sign the RAV data
  const signer = new Wallet(signerPrivateKey)
  const signature = await signer.signTypedData(domain, EIP712_RAV_PROOF_TYPES, ravData)

  // Return the signed RAV
  return { rav: ravData, signature: signature }
}

/**
 * Generates a signer proof for authorizing a signer in the Graph Tally Collector
 * @param graphTallyCollector The Graph Tally Collector contract
 * @param signer The signer
 * @param chainId The chain ID
 * @param proofDeadline The deadline for the proof
 * @param signerPrivateKey The private key of the signer
 * @returns The encoded signer proof
 */
export function generateSignerProof(
  proofDeadline: bigint,
  payer: string,
  signerPrivateKey: string,
  graphTallyCollectorAddress: string,
  chainId: number,
): string {
  // Create the message hash
  const messageHash = ethers.keccak256(
    ethers.solidityPacked(
      ['uint256', 'address', 'string', 'uint256', 'address'],
      [chainId, graphTallyCollectorAddress, 'authorizeSignerProof', proofDeadline, payer],
    ),
  )

  // Convert to EIP-191 signed message hash (this is the proofToDigest)
  const proofToDigest = ethers.hashMessage(ethers.getBytes(messageHash))

  // Sign the message
  const signer = new Wallet(signerPrivateKey)
  return Signature.from(signer.signingKey.sign(proofToDigest)).serialized
}

export function recoverReceiptSigner(
  receipt: Receipt,
  signature: Uint8Array | string,
  graphTallyCollectorAddress: string,
  chainId: number,
): string {
  // Create the domain for the EIP712 signature
  const domain = {
    name: EIP712_DOMAIN_NAME,
    version: EIP712_DOMAIN_VERSION,
    chainId,
    verifyingContract: graphTallyCollectorAddress,
  }

  // Normalize signature to 0x-hex string
  const sigHex = typeof signature === 'string' ? signature : ethers.hexlify(signature)

  // Recover the signer address from the signature
  const signerAddress = ethers.verifyTypedData(domain, EIP712_RECEIPT_PROOF_TYPES, receipt, sigHex)

  return signerAddress
}
