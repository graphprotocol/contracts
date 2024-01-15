import { toGRT } from '@graphprotocol/sdk'
import { BigNumber } from 'ethers'

import type { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

export interface SubgraphOwnerFixture {
  signer: SignerWithAddress
  ethBalance: BigNumber
  grtBalance: BigNumber
}

export interface SubgraphFixture {
  deploymentId: string
  subgraphId: string | null
}

// Test account indexes
// 2: subgraphOwner
export const getSubgraphOwner = (signers: SignerWithAddress[]): SubgraphOwnerFixture => {
  return {
    signer: signers[2],
    ethBalance: toGRT(0.1),
    grtBalance: toGRT(100_000),
  }
}

export const getSubgraphFixtures = (): SubgraphFixture[] => [
  {
    deploymentId: '0xbbde25a2c85f55b53b7698b9476610c3d1202d88870e66502ab0076b7218f98a',
    subgraphId: null,
  },
  {
    deploymentId: '0x0653445635cc1d06bd2370d2a9a072406a420d86e7fa13ea5cde100e2108b527',
    subgraphId: null,
  },
  {
    deploymentId: '0x3093dadafd593b5c2d10c16bf830e96fc41ea7b91d7dabd032b44331fb2a7e51',
    subgraphId: null,
  },
  {
    deploymentId: '0xb3fc2abc303c70a16ab9d5fc38d7e8aeae66593a87a3d971b024dd34b97e94b1',
    subgraphId: null,
  },
]
