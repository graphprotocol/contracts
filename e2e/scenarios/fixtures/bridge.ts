import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { BigNumber } from 'ethers'
import { toGRT } from '../../../cli/network'

export interface BridgeFixture {
  deploymentFile: string
  funder: SignerWithAddress
  accountsToFund: {
    signer: SignerWithAddress
    amount: BigNumber
  }[]
}

// Signers
// 0: l1Deployer
// 1: l2Deployer

export const getBridgeFixture = (signers: SignerWithAddress[]): BridgeFixture => {
  return {
    deploymentFile: 'localNetwork.json',
    funder: signers[0],
    accountsToFund: [
      {
        signer: signers[1],
        amount: toGRT(10_000_000),
      },
    ],
  }
}
