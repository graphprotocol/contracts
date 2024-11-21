import type { GraphHorizonAddressBook, GraphHorizonContracts } from './sdk/deployments/horizon'

// List of supported Graph deployments
const GraphDeploymentsList = [
  'horizon',
] as const

export type GraphDeployment = (typeof GraphDeploymentsList)[number]

export type GraphDeploymentRuntimeEnvironmentMap = {
  horizon: {
    contracts: GraphHorizonContracts
    addressBook: GraphHorizonAddressBook
  }
}

export function isGraphDeployment(deployment: unknown): deployment is GraphDeployment {
  return (
    typeof deployment === 'string'
    && GraphDeploymentsList.includes(deployment as GraphDeployment)
  )
}
