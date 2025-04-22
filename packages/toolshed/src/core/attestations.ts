import { ethers, id, toUtf8Bytes, Wallet } from "ethers"

export const EIP712_DISPUTE_MANAGER_DOMAIN_SALT = ethers.getBytes('0xa070ffb1cd7409649bf77822cce74495468e06dbfaef09556838bf188679b9c2')

export const EIP712_ATTESTATION_PROOF_TYPEHASH = id('Receipt(bytes32 requestCID,bytes32 responseCID,bytes32 subgraphDeploymentID)')
export const EIP712_ATTESTATION_PROOF_TYPES = {
  Receipt: [
    { name: 'requestCID', type: 'bytes32' },
    { name: 'responseCID', type: 'bytes32' },
    { name: 'subgraphDeploymentID', type: 'bytes32' },
  ],
}

/**
 * Creates an attestation data for a given request and response CIDs.
 * @param disputeManager The dispute manager contract instance.
 * @param requestCID The request CID.
 * @param responseCID The response CID.
 * @param signerPrivateKey The private key of the signer.
 * @param subgraphDeploymentId The subgraph deployment ID.
 * @param disputeManagerAddress The address of the dispute manager contract.
 * @param chainId The chain ID.
 * @returns The attestation data.
 */
export async function generateAttestationData(
  requestCID: string,
  responseCID: string,
  subgraphDeploymentId: string,
  signerPrivateKey: string,
  disputeManagerAddress: string,
  chainId: number,
): Promise<string> {
  // Create the domain for the EIP712 signature
  const domain = {
    name: 'Graph Protocol',
    version: '0',
    chainId: chainId,
    verifyingContract: disputeManagerAddress,
    salt: EIP712_DISPUTE_MANAGER_DOMAIN_SALT
  }

  // Create receipt struct
  const receipt = {
    requestCID: ethers.hexlify(ethers.getBytes(requestCID)),
    responseCID: ethers.hexlify(ethers.getBytes(responseCID)),
    subgraphDeploymentID: ethers.hexlify(ethers.getBytes(subgraphDeploymentId))
  }

  // Sign the receipt hash with the allocation private key
  const signer = new Wallet(signerPrivateKey)
  const signature = await signer.signTypedData(domain, EIP712_ATTESTATION_PROOF_TYPES, receipt)
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