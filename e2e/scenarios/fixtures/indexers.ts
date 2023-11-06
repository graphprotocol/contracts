import { BigNumber } from 'ethers'
import { toGRT } from '@graphprotocol/sdk'

import type { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

export interface IndexerFixture {
  signer: SignerWithAddress
  ethBalance: BigNumber
  grtBalance: BigNumber
  stake: BigNumber
  allocations: AllocationFixture[]
}

export interface AllocationFixture {
  signer: SignerWithAddress
  subgraphDeploymentId: string
  amount: BigNumber
  close: boolean
}

// Test account indexes
// 0: indexer1
// 1: indexer2
// 6: allocation1
// 7: allocation2
// 8: allocation3
// 9: allocation4
// 10: allocation5
// 11: allocation6
// 12: allocation7

export const getIndexerFixtures = (signers: SignerWithAddress[]): IndexerFixture[] => {
  return [
    // indexer1
    {
      signer: signers[0],
      ethBalance: toGRT(0.1),
      grtBalance: toGRT(100_000),
      stake: toGRT(100_000),
      allocations: [
        {
          signer: signers[6],
          subgraphDeploymentId:
            '0xbbde25a2c85f55b53b7698b9476610c3d1202d88870e66502ab0076b7218f98a',
          amount: toGRT(25_000),
          close: false,
        },
        {
          signer: signers[7],
          subgraphDeploymentId:
            '0x0653445635cc1d06bd2370d2a9a072406a420d86e7fa13ea5cde100e2108b527',
          amount: toGRT(50_000),
          close: true,
        },
        {
          signer: signers[8],
          subgraphDeploymentId:
            '0xbbde25a2c85f55b53b7698b9476610c3d1202d88870e66502ab0076b7218f98a',
          amount: toGRT(10_000),
          close: true,
        },
      ],
    },
    // indexer2
    {
      signer: signers[1],
      ethBalance: toGRT(0.1),
      grtBalance: toGRT(100_000),
      stake: toGRT(100_000),
      allocations: [
        {
          signer: signers[9],
          subgraphDeploymentId:
            '0x3093dadafd593b5c2d10c16bf830e96fc41ea7b91d7dabd032b44331fb2a7e51',
          amount: toGRT(25_000),
          close: true,
        },
        {
          signer: signers[10],
          subgraphDeploymentId:
            '0x0653445635cc1d06bd2370d2a9a072406a420d86e7fa13ea5cde100e2108b527',
          amount: toGRT(10_000),
          close: false,
        },
        {
          signer: signers[11],
          subgraphDeploymentId:
            '0x3093dadafd593b5c2d10c16bf830e96fc41ea7b91d7dabd032b44331fb2a7e51',
          amount: toGRT(10_000),
          close: true,
        },
        {
          signer: signers[12],
          subgraphDeploymentId:
            '0xb3fc2abc303c70a16ab9d5fc38d7e8aeae66593a87a3d971b024dd34b97e94b1',
          amount: toGRT(45_000),
          close: true,
        },
      ],
    },
  ]
}
