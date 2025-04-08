import type { GraphHorizonAddressBook, GraphHorizonContracts } from '@graphprotocol/toolshed/deployments/horizon'
import type { SubgraphServiceAddressBook, SubgraphServiceContracts } from '@graphprotocol/toolshed/deployments/subgraph-service'

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
