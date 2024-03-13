import { utils } from 'ethers'
import { Attestation, Receipt } from '@graphprotocol/common-ts'

export const MAX_PPM = 1000000

const { defaultAbiCoder: abi, arrayify, concat, hexlify, solidityKeccak256, joinSignature } = utils

export interface Dispute {
  id: string
  attestation: Attestation
  encodedAttestation: string
  indexerAddress: string
  receipt: Receipt
}

export function createQueryDisputeID(
  attestation: Attestation,
  indexerAddress: string,
  submitterAddress: string,
): string {
  return solidityKeccak256(
    ['bytes32', 'bytes32', 'bytes32', 'address', 'address'],
    [
      attestation.requestCID,
      attestation.responseCID,
      attestation.subgraphDeploymentID,
      indexerAddress,
      submitterAddress,
    ],
  )
}

export function encodeAttestation(attestation: Attestation): string {
  const data = arrayify(
    abi.encode(
      ['bytes32', 'bytes32', 'bytes32'],
      [attestation.requestCID, attestation.responseCID, attestation.subgraphDeploymentID],
    ),
  )
  const sig = joinSignature(attestation)
  return hexlify(concat([data, sig]))
}
