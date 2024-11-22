import type { GraphHorizonAddressBook, GraphHorizonContracts } from './sdk/deployments/horizon'

// List of supported Graph deployments
export const GraphDeploymentsList = [
  'horizon',
] as const

export type GraphDeploymentRuntimeEnvironmentMap = {
  horizon: {
    contracts: GraphHorizonContracts
    addressBook: GraphHorizonAddressBook
  }
}
