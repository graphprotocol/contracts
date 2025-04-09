import { GraphDeploymentsList } from '@graphprotocol/toolshed/deployments'

import type { GraphDeploymentName, GraphDeployments } from '@graphprotocol/toolshed/deployments'
import type { HardhatEthersProvider } from '@nomicfoundation/hardhat-ethers/internal/hardhat-ethers-provider'

export type GraphDeploymentOptions = {
  [deployment in GraphDeploymentName]?: string
}

export type GraphRuntimeEnvironmentOptions = {
  deployments?: GraphDeploymentOptions
}

export type GraphRuntimeEnvironment = GraphDeployments & {
  provider: HardhatEthersProvider
  chainId: number
}

export function isGraphDeployment(deployment: unknown): deployment is GraphDeploymentName {
  return typeof deployment === 'string' && GraphDeploymentsList.includes(deployment as GraphDeploymentName)
}

export function assertGraphRuntimeEnvironment(
  obj: unknown,
): obj is GraphRuntimeEnvironment {
  if (typeof obj !== 'object' || obj === null) return false

  const deployments = obj as GraphDeployments

  for (const deployment in deployments) {
    const environment = deployments[deployment as keyof GraphDeployments]
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
