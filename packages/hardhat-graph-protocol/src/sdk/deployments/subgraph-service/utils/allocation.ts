import { Wallet, Signature } from 'ethers'

import { ISubgraphService } from '@graphprotocol/subgraph-service'

/**
 * Generates an allocation proof
 * @param subgraphService The subgraph service contract
 * @param indexerAddress The address of the indexer
 * @param allocationPrivateKey The private key of the allocation
 * @returns The encoded allocation proof
 */
export async function generateAllocationProof(
  subgraphService: ISubgraphService,
  indexerAddress: string,
  allocationPrivateKey: string,
): Promise<string> {
  const wallet = new Wallet(allocationPrivateKey)
  const messageHash = await subgraphService.encodeAllocationProof(indexerAddress, wallet.address)
  const signature = wallet.signingKey.sign(messageHash)
  return Signature.from(signature).serialized
}