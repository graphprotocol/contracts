import { parseEther } from 'ethers'

// Indexer interface
export interface Indexer {
  address: string
  stake: bigint
  tokensToUnstake?: bigint
  indexingRewardCut: number
  queryFeeCut: number
  rewardsDestination?: string
  allocations: Allocation[]
}

// Allocation interface
export interface Allocation {
  allocationID: string
  allocationPrivateKey: string
  subgraphDeploymentID: string
  tokens: bigint
}

// Indexer one data
const INDEXER_ONE_ADDRESS = '0x95cED938F7991cd0dFcb48F0a06a40FA1aF46EBC' // Hardhat account #5
const INDEXER_ONE_FIRST_ALLOCATION_ID = '0x70043e424171076D74a1f6a6a56087Bb4c7A61AA'
const INDEXER_ONE_FIRST_ALLOCATION_PRIVATE_KEY = '0x9c41bca4eb319bdf4cac23ae3366eed5f9fa12eb05c0ef29319afcfaa3fc2d79'
const INDEXER_ONE_SECOND_ALLOCATION_ID = '0xd67CE7F6A2eCa6fD78A7E2A5C5e56Fb821BEdE0c'
const INDEXER_ONE_SECOND_ALLOCATION_PRIVATE_KEY = '0x827a0b66fbeb3fefb4a99b6ba0b4bea3b8dd590b97fa7a1bbe74e5b33c935f16'
const INDEXER_ONE_THIRD_ALLOCATION_ID = '0x212e51125e4Ed4C2041614b139eC6cb8FA6d561C'
const INDEXER_ONE_THIRD_ALLOCATION_PRIVATE_KEY = '0x434f1d4435e978299ec64841153c25af2f611a145da3e8539c65b9bd5d9c08b5'

// Indexer two data
const INDEXER_TWO_ADDRESS = '0x3E5e9111Ae8eB78Fe1CC3bb8915d5D461F3Ef9A9' // Hardhat account #6
const INDEXER_TWO_REWARDS_DESTINATION = '0x227A35f9912693240E842FaAB6cf5e4E6371ff63'
const INDEXER_TWO_FIRST_ALLOCATION_ID = '0xD0EAc83b0bf328bbf68F4f1a1480e17A38BFb192'
const INDEXER_TWO_FIRST_ALLOCATION_PRIVATE_KEY = '0x80ff89a67cf4b41ea3ece2574b7212b5fee43c0fa370bf3e188a645b561ac810'
const INDEXER_TWO_SECOND_ALLOCATION_ID = '0x63280ec9EA63859b7e2041f07a549F311C86B3bd'
const INDEXER_TWO_SECOND_ALLOCATION_PRIVATE_KEY = '0xab6cb9dbb3646a856e6cac2c0e2a59615634e93cde11385eb6c6ba58e2873a46'

// Indexer three data
const INDEXER_THREE_ADDRESS = '0x28a8746e75304c0780E011BEd21C72cD78cd535E' // Hardhat account #6
const INDEXER_THREE_REWARDS_DESTINATION = '0xA3D22DDf431A8745888804F520D4eA51Cb43A458'
// Subgraph deployment IDs
const SUBGRAPH_DEPLOYMENT_ID_ONE = '0x02cd85012c1f075fd58fad178fd23ab841d3b5ddcf5cd3377c30118da97cb2a4'
const SUBGRAPH_DEPLOYMENT_ID_TWO = '0x03ca89485a59894f1acfa34660c69024b6b90ce45171dece7662b0886bc375c7'
const SUBGRAPH_DEPLOYMENT_ID_THREE = '0x0472e8c46f728adb65a22187c6740532f82c2ebadaeabbbe59a2bb4a1bdde197'

export const indexers: Indexer[] = [
  {
    address: INDEXER_ONE_ADDRESS,
    stake: parseEther('1100000'),
    tokensToUnstake: parseEther('10000'),
    indexingRewardCut: 900000, // 90%
    queryFeeCut: 900000, // 90%
    allocations: [
      {
        allocationID: INDEXER_ONE_FIRST_ALLOCATION_ID,
        allocationPrivateKey: INDEXER_ONE_FIRST_ALLOCATION_PRIVATE_KEY,
        subgraphDeploymentID: SUBGRAPH_DEPLOYMENT_ID_ONE,
        tokens: parseEther('400000'),
      },
      {
        allocationID: INDEXER_ONE_SECOND_ALLOCATION_ID,
        allocationPrivateKey: INDEXER_ONE_SECOND_ALLOCATION_PRIVATE_KEY,
        subgraphDeploymentID: SUBGRAPH_DEPLOYMENT_ID_TWO,
        tokens: parseEther('300000'),
      },
      {
        allocationID: INDEXER_ONE_THIRD_ALLOCATION_ID,
        allocationPrivateKey: INDEXER_ONE_THIRD_ALLOCATION_PRIVATE_KEY,
        subgraphDeploymentID: SUBGRAPH_DEPLOYMENT_ID_THREE,
        tokens: parseEther('250000'),
      },
    ],
  },
  {
    address: INDEXER_TWO_ADDRESS,
    stake: parseEther('1100000'),
    tokensToUnstake: parseEther('1000000'),
    indexingRewardCut: 850000, // 85%
    queryFeeCut: 850000, // 85%
    rewardsDestination: INDEXER_TWO_REWARDS_DESTINATION,
    allocations: [
      {
        allocationID: INDEXER_TWO_FIRST_ALLOCATION_ID,
        allocationPrivateKey: INDEXER_TWO_FIRST_ALLOCATION_PRIVATE_KEY,
        subgraphDeploymentID: SUBGRAPH_DEPLOYMENT_ID_ONE,
        tokens: parseEther('400000'),
      },
      {
        allocationID: INDEXER_TWO_SECOND_ALLOCATION_ID,
        allocationPrivateKey: INDEXER_TWO_SECOND_ALLOCATION_PRIVATE_KEY,
        subgraphDeploymentID: SUBGRAPH_DEPLOYMENT_ID_TWO,
        tokens: parseEther('200000'),
      },
    ],
  },
  {
    address: INDEXER_THREE_ADDRESS,
    stake: parseEther('1100000'),
    indexingRewardCut: 800000, // 80%
    queryFeeCut: 800000, // 80%
    rewardsDestination: INDEXER_THREE_REWARDS_DESTINATION,
    allocations: [],
  },
]
