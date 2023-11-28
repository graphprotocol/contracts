import { toGRT } from '@graphprotocol/sdk'
import { BigNumber } from 'ethers'

import type { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

export interface CuratorFixture {
  signer: SignerWithAddress
  ethBalance: BigNumber
  grtBalance: BigNumber
  signalled: BigNumber
  subgraphs: SubgraphFixture[]
}

export interface SubgraphFixture {
  deploymentId: string
  signal: BigNumber
}

// Test account indexes
// 3: curator1
// 4: curator2
// 5: curator3

export const getCuratorFixtures = (signers: SignerWithAddress[]): CuratorFixture[] => {
  return [
    // curator1
    {
      signer: signers[3],
      ethBalance: toGRT(0.1),
      grtBalance: toGRT(100_000),
      signalled: toGRT(10_400),
      subgraphs: [
        {
          deploymentId: '0x0653445635cc1d06bd2370d2a9a072406a420d86e7fa13ea5cde100e2108b527',
          signal: toGRT(400),
        },
        {
          deploymentId: '0x3093dadafd593b5c2d10c16bf830e96fc41ea7b91d7dabd032b44331fb2a7e51',
          signal: toGRT(4_000),
        },
        {
          deploymentId: '0xb3fc2abc303c70a16ab9d5fc38d7e8aeae66593a87a3d971b024dd34b97e94b1',
          signal: toGRT(6_000),
        },
      ],
    },
    // curator2
    {
      signer: signers[4],
      ethBalance: toGRT(0.1),
      grtBalance: toGRT(100_000),
      signalled: toGRT(4_500),
      subgraphs: [
        {
          deploymentId: '0x3093dadafd593b5c2d10c16bf830e96fc41ea7b91d7dabd032b44331fb2a7e51',
          signal: toGRT(2_000),
        },
        {
          deploymentId: '0xb3fc2abc303c70a16ab9d5fc38d7e8aeae66593a87a3d971b024dd34b97e94b1',
          signal: toGRT(2_500),
        },
      ],
    },
    // curator3
    {
      signer: signers[5],
      ethBalance: toGRT(0.1),
      grtBalance: toGRT(100_000),
      signalled: toGRT(8_000),
      subgraphs: [
        {
          deploymentId: '0x3093dadafd593b5c2d10c16bf830e96fc41ea7b91d7dabd032b44331fb2a7e51',
          signal: toGRT(4_000),
        },
        {
          deploymentId: '0xb3fc2abc303c70a16ab9d5fc38d7e8aeae66593a87a3d971b024dd34b97e94b1',
          signal: toGRT(4_000),
        },
      ],
    },
  ]
}
