import {
  execute,
  AllocationsDocument,
  AllocationsQuery,
  AllocationsAtBlockQuery,
  AllocationsAtBlockDocument,
} from '../../.graphclient'
import * as GraphClient from '../../.graphclient'

import { ExecutionResult } from 'graphql'

export type ActiveAllocation = Pick<
  GraphClient.Allocation,
  'id' | 'allocatedTokens' | 'createdAt' | 'createdAtEpoch' | 'createdAtBlockNumber'
> & {
  subgraphDeployment: Pick<GraphClient.SubgraphDeployment, 'id'>
  indexer: Pick<GraphClient.Indexer, 'id' | 'stakedTokens'>
}

export async function getActiveAllocations(
  networkSubgraph: string,
  blockNumber?: number,
): Promise<ActiveAllocation[]> {
  const executeVariables = blockNumber ? { first: 5_000, block: blockNumber } : { first: 5_000 }
  const executeDocument = blockNumber ? AllocationsAtBlockDocument : AllocationsDocument

  const result: ExecutionResult<AllocationsQuery | AllocationsAtBlockQuery> = await execute(
    executeDocument,
    executeVariables, // TODO: getting error if using a higher count -> The `skip` argument must be between 0 and 5000, but is 6000
    { networkSubgraph },
  )

  return result.data ? result.data.allocations : []
}
