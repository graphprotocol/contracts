import type { GraphHorizonRuntimeEnvironment } from './sdk/deployments/horizon'

export const GraphDeploymentsList = [
  'horizon',
] as const

export type GraphDeployment = (typeof GraphDeploymentsList)[number]

export function isGraphDeployment(deployment: unknown): deployment is GraphDeployment {
  return (
    typeof deployment === 'string'
    && GraphDeploymentsList.includes(deployment as GraphDeployment)
  )
}

export type GraphRuntimeEnvironmentOptions = {
  addressBooks?: {
    [deployment in GraphDeployment]: string
  }
}

export type GraphRuntimeEnvironment = {
  [deployment in GraphDeployment]: GraphHorizonRuntimeEnvironment
}
