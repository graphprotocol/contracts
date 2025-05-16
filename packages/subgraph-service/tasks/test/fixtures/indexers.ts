import { indexers as horizonIndexers } from '../../../../horizon/tasks/test/fixtures/indexers'
import { parseEther } from 'ethers'

// Allocation interface
export interface Allocation {
  allocationID: string
  subgraphDeploymentID: string
  allocationPrivateKey: string
  tokens: bigint
}

// Indexer interface
export interface Indexer {
  address: string
  indexingRewardCut: number
  queryFeeCut: number
  url: string
  geoHash: string
  rewardsDestination?: string
  provisionTokens: bigint
  legacyAllocations: Allocation[]
  allocations: Allocation[]
}

// Subgraph deployment IDs
const SUBGRAPH_DEPLOYMENT_ID_ONE = '0x02cd85012c1f075fd58fad178fd23ab841d3b5ddcf5cd3377c30118da97cb2a4'
const SUBGRAPH_DEPLOYMENT_ID_TWO = '0x03ca89485a59894f1acfa34660c69024b6b90ce45171dece7662b0886bc375c7'
const SUBGRAPH_DEPLOYMENT_ID_THREE = '0x0472e8c46f728adb65a22187c6740532f82c2ebadaeabbbe59a2bb4a1bdde197'

// Indexer one allocations
const INDEXER_ONE_FIRST_ALLOCATION_ID = '0x097DC23d51A7800f9B1EA37919A5b223C0224eC2'
const INDEXER_ONE_FIRST_ALLOCATION_PRIVATE_KEY = '0xec5739112bc20845cdd80b2612dfb0a75599ea6fbdd8916a1e7d5be98118c315'
const INDEXER_ONE_SECOND_ALLOCATION_ID = '0x897E7056FB86372CB676EBAE73a360c22b21D4aD'
const INDEXER_ONE_SECOND_ALLOCATION_PRIVATE_KEY = '0x298519bdc6a73f0d64c96e1f7c39aba3f825886a37e0349294ce7c407bd88370'
const INDEXER_ONE_THIRD_ALLOCATION_ID = '0x02C64e54100b3Cb324ac50d9b3823402e6aA5297'
const INDEXER_ONE_THIRD_ALLOCATION_PRIVATE_KEY = '0xb8ca0ab93098c2c478c5657da7a7bb89522bb1e3198f8b469de252dfee5469a3'

// Indexer two allocations
const INDEXER_TWO_FIRST_ALLOCATION_ID = '0xB609bBf1D5Ae3C246dA1F9a5EA327DBa66BbcB05'
const INDEXER_TWO_FIRST_ALLOCATION_PRIVATE_KEY = '0x21dce628700b82e2d9045d756e4d0ba736f652a170655398a15fadae10b0e846'
const INDEXER_TWO_SECOND_ALLOCATION_ID = '0x1bF6afCF9542983432B2fab15717c2537A3d3F2A'
const INDEXER_TWO_SECOND_ALLOCATION_PRIVATE_KEY = '0x4bf454f7d52fff97701c1ea5d1e6184c81543780ca61b82cce155a5a3e35a134'

// Allocations map
const allocations = new Map<string, Allocation[]>([
  [
    horizonIndexers[0].address,
    [
      {
        allocationID: INDEXER_ONE_FIRST_ALLOCATION_ID,
        subgraphDeploymentID: SUBGRAPH_DEPLOYMENT_ID_ONE,
        allocationPrivateKey: INDEXER_ONE_FIRST_ALLOCATION_PRIVATE_KEY,
        tokens: parseEther('10000'),
      },
      {
        allocationID: INDEXER_ONE_SECOND_ALLOCATION_ID,
        subgraphDeploymentID: SUBGRAPH_DEPLOYMENT_ID_TWO,
        allocationPrivateKey: INDEXER_ONE_SECOND_ALLOCATION_PRIVATE_KEY,
        tokens: parseEther('8000'),
      },
      {
        allocationID: INDEXER_ONE_THIRD_ALLOCATION_ID,
        subgraphDeploymentID: SUBGRAPH_DEPLOYMENT_ID_THREE,
        allocationPrivateKey: INDEXER_ONE_THIRD_ALLOCATION_PRIVATE_KEY,
        tokens: parseEther('5000'),
      },
    ],
  ],
  [
    horizonIndexers[2].address,
    [
      {
        allocationID: INDEXER_TWO_FIRST_ALLOCATION_ID,
        subgraphDeploymentID: SUBGRAPH_DEPLOYMENT_ID_ONE,
        allocationPrivateKey: INDEXER_TWO_FIRST_ALLOCATION_PRIVATE_KEY,
        tokens: parseEther('10000'),
      },
      {
        allocationID: INDEXER_TWO_SECOND_ALLOCATION_ID,
        subgraphDeploymentID: SUBGRAPH_DEPLOYMENT_ID_TWO,
        allocationPrivateKey: INDEXER_TWO_SECOND_ALLOCATION_PRIVATE_KEY,
        tokens: parseEther('8000'),
      },
    ],
  ],
])

// Indexers data
export const indexers: Indexer[] = horizonIndexers
  .filter(indexer => !indexer.tokensToUnstake || indexer.tokensToUnstake <= parseEther('100000'))
  .map((indexer) => {
    // Move existing allocations to legacyAllocations
    const legacyAllocations = indexer.allocations

    // Previsouly cuts were indexer's share, Horizon cuts are delegator's share. Invert values:
    // 1_000_000 - oldValue converts from "indexer keeps X%" to "delegators get X%"
    const maxPpm = 1_000_000
    const indexingRewardCut = maxPpm - indexer.indexingRewardCut
    const queryFeeCut = maxPpm - indexer.queryFeeCut

    return {
      ...indexer,
      indexingRewardCut,
      queryFeeCut,
      url: 'url',
      geoHash: 'geohash',
      provisionTokens: parseEther('1000000'),
      legacyAllocations,
      allocations: allocations.get(indexer.address) || [],
    }
  })
