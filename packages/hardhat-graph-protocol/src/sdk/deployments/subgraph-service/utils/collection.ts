import { BytesLike, ethers, HDNodeWallet, Signature } from 'ethers'

import { IGraphTallyCollector } from '@graphprotocol/subgraph-service'

/**
 * Generates a signed RAV calldata
 * @param graphTallyCollector The Graph Tally Collector contract
 * @param signer The signer
 * @param collectionId The collection ID
 * @param payer The payer
 * @param serviceProvider The service provider
 * @param dataService The data service
 * @param timestampNs The timestamp in nanoseconds
 * @param valueAggregate The value aggregate
 * @param metadata The metadata
 * @returns The encoded signed RAV calldata
 */
export async function getSignedRAVCalldata(
  graphTallyCollector: IGraphTallyCollector,
  signer: HDNodeWallet,
  allocationId: string,
  payer: string,
  serviceProvider: string,
  dataService: string,
  timestampNs: number,
  valueAggregate: bigint,
  metadata: BytesLike
) {
  const ravData = {
    collectionId: ethers.zeroPadValue(allocationId, 32),
    payer: payer,
    serviceProvider: serviceProvider,
    dataService: dataService,
    timestampNs: timestampNs,
    valueAggregate: valueAggregate,
    metadata: metadata
  }

  const encodedRAV = await graphTallyCollector.encodeRAV(ravData)
  const messageHash = ethers.getBytes(encodedRAV)
  const signature = ethers.Signature.from(signer.signingKey.sign(messageHash)).serialized
  const signedRAV = { rav: ravData, signature }
  return ethers.AbiCoder.defaultAbiCoder().encode(
    ['tuple(tuple(bytes32 collectionId, address payer, address serviceProvider, address dataService, uint256 timestampNs, uint128 valueAggregate, bytes metadata) rav, bytes signature)'],
    [signedRAV]
  )
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
export async function getSignerProof(
  graphTallyCollector: IGraphTallyCollector,
  signer: HDNodeWallet,
  chainId: bigint,
  proofDeadline: bigint,
  payer: string
): Promise<string> {
  // Create the message hash
  const messageHash = ethers.keccak256(
    ethers.solidityPacked(
      ['uint256', 'address', 'string', 'uint256', 'address'],
      [
        chainId,
        await graphTallyCollector.getAddress(),
        'authorizeSignerProof',
        proofDeadline,
        payer
      ]
    )
  )

  // Convert to EIP-191 signed message hash (this is the proofToDigest)
  const proofToDigest = ethers.hashMessage(ethers.getBytes(messageHash))

  // Sign the message
  return Signature.from(signer.signingKey.sign(proofToDigest)).serialized
}
