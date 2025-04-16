import { ethers, Wallet } from "ethers"

import { IDisputeManager } from "@graphprotocol/subgraph-service"

/**
 * Creates an attestation data for a given request and response CIDs.
 * @param disputeManager The dispute manager contract instance.
 * @param signer The allocation ID that will be signing the attestation.
 * @param requestCID The request CID.
 * @param responseCID The response CID.
 * @param subgraphDeploymentId The subgraph deployment ID.
 * @returns The attestation data.
 */
export async function createAttestationData(
  disputeManager: IDisputeManager,
  signer: Wallet,
  requestCID: string,
  responseCID: string,
  subgraphDeploymentId: string
): Promise<string> {
  // Create receipt struct
  const receipt = {
    requestCID,
    responseCID,
    subgraphDeploymentId
  }

  // Encode the receipt using the dispute manager
  const receiptHash = await disputeManager.encodeReceipt(receipt)

  // Sign the receipt hash with the allocation private key
  const signature = signer.signingKey.sign(ethers.getBytes(receiptHash))
  const sig = ethers.Signature.from(signature)

  // Concatenate the bytes directly
  return ethers.concat([
    ethers.getBytes(requestCID),
    ethers.getBytes(responseCID),
    ethers.getBytes(subgraphDeploymentId),
    ethers.getBytes(sig.r),
    ethers.getBytes(sig.s),
    new Uint8Array([sig.v])
  ])
}