import type { GraphHorizonAddressBook, GraphHorizonContracts } from './horizon'
import type { SubgraphServiceAddressBook, SubgraphServiceContracts } from './subgraph-service'
import type { loadActions } from './horizon/actions'
import type { loadActions as loadSubgraphServiceActions } from './subgraph-service/actions'
export const GraphDeploymentsList = ['horizon', 'subgraphService'] as const

export type GraphDeploymentName = (typeof GraphDeploymentsList)[number]

export type GraphDeployments = {
  horizon: {
    contracts: GraphHorizonContracts
    addressBook: GraphHorizonAddressBook
    actions: ReturnType<typeof loadActions>
  }
  subgraphService: {
    contracts: SubgraphServiceContracts
    addressBook: SubgraphServiceAddressBook
    actions: ReturnType<typeof loadSubgraphServiceActions>
  }
}
