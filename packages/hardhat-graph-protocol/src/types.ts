import { type GraphDeploymentRuntimeEnvironmentMap, GraphDeploymentsList } from './deployment-list'
import type { HardhatEthersProvider } from '@nomicfoundation/hardhat-ethers/internal/hardhat-ethers-provider'

export type GraphDeployment = (typeof GraphDeploymentsList)[number]

export type GraphDeployments = {
  [deployment in GraphDeployment]?: string | {
    addressBook: string
  }
}

export type GraphRuntimeEnvironmentOptions = {
  deployments?: {
    [deployment in GraphDeployment]?: string | {
      addressBook: string
    }
  }
}

export type GraphRuntimeEnvironment = {
  [deployment in keyof GraphDeploymentRuntimeEnvironmentMap]?: GraphDeploymentRuntimeEnvironmentMap[deployment]
} & {
  provider: HardhatEthersProvider
  chainId: number
}

export function isGraphDeployment(deployment: unknown): deployment is GraphDeployment {
  return (
    typeof deployment === 'string'
    && GraphDeploymentsList.includes(deployment as GraphDeployment)
  )
}

export function assertGraphRuntimeEnvironment(
  obj: unknown,
): obj is GraphRuntimeEnvironment {
  if (typeof obj !== 'object' || obj === null) return false

  const deployments = obj as Partial<GraphDeploymentRuntimeEnvironmentMap>

  for (const deployment in deployments) {
    const environment = deployments[deployment as keyof GraphDeploymentRuntimeEnvironmentMap]
    if (!environment || typeof environment !== 'object') {
      return false
    }
  }

  if (typeof (obj as GraphRuntimeEnvironment).provider !== 'object') {
    return false
  }

  if (typeof (obj as GraphRuntimeEnvironment).chainId !== 'function') {
    return false
  }

  return true
}
