// To extend one of Hardhat's types, you need to import the module where it has been defined, and redeclare it.
import 'hardhat/types/config'
import 'hardhat/types/runtime'

import type { GraphDeployment, GraphDeploymentRuntimeEnvironmentMap } from './deployments'
import type { HardhatEthersProvider } from '@nomicfoundation/hardhat-ethers/internal/hardhat-ethers-provider'

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
  chainId: () => Promise<bigint>
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

declare module 'hardhat/types/runtime' {
  export interface HardhatRuntimeEnvironment {
    graph: (opts?: GraphRuntimeEnvironmentOptions) => GraphRuntimeEnvironment
  }
}

declare module 'hardhat/types/config' {
  export interface HardhatConfig {
    graph: GraphRuntimeEnvironmentOptions
  }

  export interface HardhatUserConfig {
    graph: GraphRuntimeEnvironmentOptions
  }

  export interface HardhatNetworkConfig {
    deployments?: {
      [deployment in GraphDeployment]?: string | {
        addressBook: string
      }
    }
  }

  export interface HardhatNetworkUserConfig {
    deployments?: {
      [deployment in GraphDeployment]?: string | {
        addressBook: string
      }
    }
  }

  export interface HttpNetworkConfig {
    deployments?: {
      [deployment in GraphDeployment]?: string | {
        addressBook: string
      }
    }
  }

  export interface HttpNetworkUserConfig {
    deployments?: {
      [deployment in GraphDeployment]?: string | {
        addressBook: string
      }
    }
  }

  export interface ProjectPathsConfig {
    graph?: string
  }

  export interface ProjectPathsUserConfig {
    graph?: string
  }
}
