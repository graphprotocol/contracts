// To extend one of Hardhat's types, you need to import the module where it has been defined, and redeclare it.
import 'hardhat/types/config'
import 'hardhat/types/runtime'

import type { GraphRuntimeEnvironment, GraphRuntimeEnvironmentOptions } from './types'

declare module 'hardhat/types/runtime' {
  export interface HardhatRuntimeEnvironment {
    graph: (opts?: GraphRuntimeEnvironmentOptions) => GraphRuntimeEnvironment
  }
}

declare module 'hardhat/types/config' {
  export interface HardhatConfig {
    graph: Omit<GraphRuntimeEnvironmentOptions, 'graphConfig'>
  }

  export interface HardhatUserConfig {
    graph: Omit<GraphRuntimeEnvironmentOptions, 'graphConfig'>
  }

  export interface HardhatNetworkConfig {
    graphConfig?: string
    addressBook?: string
  }

  export interface HardhatNetworkUserConfig {
    graphConfig?: string
    addressBook?: string
  }

  export interface HttpNetworkConfig {
    graphConfig?: string
    addressBook?: string
  }

  export interface HttpNetworkUserConfig {
    graphConfig?: string
    addressBook?: string
  }

  export interface ProjectPathsConfig {
    graph?: string
  }

  export interface ProjectPathsUserConfig {
    graph?: string
  }
}
