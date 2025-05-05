import { utils, Wallet } from 'ethers'
import type { Signer } from 'ethers'

export enum AllocationState {
  Null,
  Active,
  Closed,
  Finalized,
  Claimed,
}

export interface ChannelKey {
  privKey: string
  pubKey: string
  address: string
  wallet: Signer
  generateProof: (address: string) => Promise<string>
}

export const deriveChannelKey = (): ChannelKey => {
  const w = Wallet.createRandom()
  return {
    privKey: w.privateKey,
    pubKey: w.publicKey,
    address: w.address,
    wallet: w,
    generateProof: (indexerAddress: string): Promise<string> => {
      const messageHash = utils.solidityKeccak256(
        ['address', 'address'],
        [indexerAddress, w.address],
      )
      const messageHashBytes = utils.arrayify(messageHash)
      return w.signMessage(messageHashBytes)
    },
  }
}
