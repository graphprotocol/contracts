// To extend one of Hardhat's types, you need to import the module where it has been defined, and redeclare it.
import 'hardhat/types/config'
import 'hardhat/types/runtime'
import type { GraphDeployments, GraphRuntimeEnvironment, GraphRuntimeEnvironmentOptions } from './types'

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
