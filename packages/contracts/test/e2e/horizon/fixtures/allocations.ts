import { parseEther, keccak256, toUtf8Bytes } from 'ethers/lib/utils'
import { indexers } from './indexers'
import { BigNumber } from 'ethers'

export interface Allocation {
  indexerAddress: string
  allocationID: string
  allocationPrivateKey: string
  subgraphDeploymentID: string
  tokens: BigNumber 
}

// Indexer one data
const INDEXER_ONE_FIRST_ALLOCATION_ID = '0x70043e424171076D74a1f6a6a56087Bb4c7A61AA'
const INDEXER_ONE_FIRST_ALLOCATION_PRIVATE_KEY = '0x9c41bca4eb319bdf4cac23ae3366eed5f9fa12eb05c0ef29319afcfaa3fc2d79'
const INDEXER_ONE_SECOND_ALLOCATION_ID = '0xd67CE7F6A2eCa6fD78A7E2A5C5e56Fb821BEdE0c'
const INDEXER_ONE_SECOND_ALLOCATION_PRIVATE_KEY = '0x827a0b66fbeb3fefb4a99b6ba0b4bea3b8dd590b97fa7a1bbe74e5b33c935f16'
const INDEXER_ONE_THIRD_ALLOCATION_ID = '0x212e51125e4Ed4C2041614b139eC6cb8FA6d561C'
const INDEXER_ONE_THIRD_ALLOCATION_PRIVATE_KEY = '0x434f1d4435e978299ec64841153c25af2f611a145da3e8539c65b9bd5d9c08b5'

// Indexer two data
const INDEXER_TWO_FIRST_ALLOCATION_ID = '0xD0EAc83b0bf328bbf68F4f1a1480e17A38BFb192'
const INDEXER_TWO_FIRST_ALLOCATION_PRIVATE_KEY = '0x80ff89a67cf4b41ea3ece2574b7212b5fee43c0fa370bf3e188a645b561ac810'
const INDEXER_TWO_SECOND_ALLOCATION_ID = '0x63280ec9EA63859b7e2041f07a549F311C86B3bd'
const INDEXER_TWO_SECOND_ALLOCATION_PRIVATE_KEY = '0xab6cb9dbb3646a856e6cac2c0e2a59615634e93cde11385eb6c6ba58e2873a46'

// Subgraph deployment IDs
const SUBGRAPH_DEPLOYMENT_ID_ONE = keccak256(toUtf8Bytes("subgraphDeploymentID1"))
const SUBGRAPH_DEPLOYMENT_ID_TWO = keccak256(toUtf8Bytes("subgraphDeploymentID2"))
const SUBGRAPH_DEPLOYMENT_ID_THREE = keccak256(toUtf8Bytes("subgraphDeploymentID3"))

export const allocations: Allocation[] = [
  // Allocations for first indexer
  {
    indexerAddress: indexers[0].address,
    allocationID: INDEXER_ONE_FIRST_ALLOCATION_ID,
    allocationPrivateKey: INDEXER_ONE_FIRST_ALLOCATION_PRIVATE_KEY,
    subgraphDeploymentID: SUBGRAPH_DEPLOYMENT_ID_ONE,
    tokens: parseEther('400000'),
  },
  {
    indexerAddress: indexers[0].address,
    allocationID: INDEXER_ONE_SECOND_ALLOCATION_ID,
    allocationPrivateKey: INDEXER_ONE_SECOND_ALLOCATION_PRIVATE_KEY,
    subgraphDeploymentID: SUBGRAPH_DEPLOYMENT_ID_TWO,
    tokens: parseEther('300000'),
  },
  {
    indexerAddress: indexers[1].address,
    allocationID: INDEXER_ONE_THIRD_ALLOCATION_ID,
    allocationPrivateKey: INDEXER_ONE_THIRD_ALLOCATION_PRIVATE_KEY,
    subgraphDeploymentID: SUBGRAPH_DEPLOYMENT_ID_THREE,
    tokens: parseEther('250000'),
  },
  
  // Allocations for second indexer
  {
    indexerAddress: indexers[1].address,
    allocationID: INDEXER_TWO_FIRST_ALLOCATION_ID,
    allocationPrivateKey: INDEXER_TWO_FIRST_ALLOCATION_PRIVATE_KEY,
    subgraphDeploymentID: SUBGRAPH_DEPLOYMENT_ID_ONE,
    tokens: parseEther('400000'),
  },
  {
    indexerAddress: indexers[1].address,
    allocationID: INDEXER_TWO_SECOND_ALLOCATION_ID,
    allocationPrivateKey: INDEXER_TWO_SECOND_ALLOCATION_PRIVATE_KEY,
    subgraphDeploymentID: SUBGRAPH_DEPLOYMENT_ID_TWO,
    tokens: parseEther('200000'),
  },
]