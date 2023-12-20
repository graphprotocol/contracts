import { toGRT } from '@graphprotocol/sdk'
import { BigNumber } from 'ethers'

import type { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

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
