// TypeScript does not resolve correctly the type extensions when they are symlinked from the same monorepo.
// So we need to re-type it... this file should be a copy of hardhat-graph-protocol/src/type-extensions.ts
import 'hardhat/types/config'
import 'hardhat/types/runtime'
import type { GraphDeployments, GraphRuntimeEnvironment, GraphRuntimeEnvironmentOptions } from 'hardhat-graph-protocol'

declare module 'hardhat/types/runtime' {
  interface HardhatRuntimeEnvironment {
    graph: (opts?: GraphRuntimeEnvironmentOptions) => GraphRuntimeEnvironment
  }
}

declare module 'hardhat/types/config' {
  interface HardhatConfig {
    graph: GraphRuntimeEnvironmentOptions
  }

  interface HardhatUserConfig {
    graph: GraphRuntimeEnvironmentOptions
  }

  interface HardhatNetworkConfig {
    deployments?: GraphDeployments
  }

  interface HardhatNetworkUserConfig {
    deployments?: GraphDeployments
  }

  interface HttpNetworkConfig {
    deployments?: GraphDeployments
  }

  interface HttpNetworkUserConfig {
    deployments?: GraphDeployments
  }

  interface ProjectPathsConfig {
    graph?: string
  }

  interface ProjectPathsUserConfig {
    graph?: string
  }
}
