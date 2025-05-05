import {
  createAttestation,
  encodeAttestation as encodeAttestationLib,
  Attestation,
  Receipt,
} from '@graphprotocol/common-ts'
import { GraphChainId } from '../../../chain'

export async function buildAttestation(
  receipt: Receipt,
  signer: string,
  disputeManagerAddress: string,
  chainId: GraphChainId,
) {
  return await createAttestation(signer, chainId, disputeManagerAddress, receipt, '0')
}

export function encodeAttestation(attestation: Attestation): string {
  return encodeAttestationLib(attestation)
}
