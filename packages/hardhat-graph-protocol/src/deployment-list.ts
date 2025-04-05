import type { GraphHorizonAddressBook, GraphHorizonContracts } from '../../toolshed/src/deployments'
import type { SubgraphServiceAddressBook, SubgraphServiceContracts } from '../../toolshed/src/deployments/subgraph-service'

// List of supported Graph deployments
export const GraphDeploymentsList = [
  'horizon',
  'subgraphService',
] as const

export type GraphDeploymentRuntimeEnvironmentMap = {
  horizon: {
    contracts: GraphHorizonContracts
    addressBook: GraphHorizonAddressBook
  }
  subgraphService: {
    contracts: SubgraphServiceContracts
    addressBook: SubgraphServiceAddressBook
  }
}
