// To extend one of Hardhat's types, you need to import the module where it has been defined, and redeclare it.
import 'hardhat/types/config'
import 'hardhat/types/runtime'

import type { GraphDeploymentOptions, GraphRuntimeEnvironment, GraphRuntimeEnvironmentOptions } from './types'

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
    deployments?: GraphDeploymentOptions
  }

  interface HardhatNetworkUserConfig {
    deployments?: GraphDeploymentOptions
  }

  interface HttpNetworkConfig {
    deployments?: GraphDeploymentOptions
  }

  interface HttpNetworkUserConfig {
    deployments?: GraphDeploymentOptions
  }

  interface ProjectPathsConfig {
    graph?: string
  }

  interface ProjectPathsUserConfig {
    graph?: string
  }
}
