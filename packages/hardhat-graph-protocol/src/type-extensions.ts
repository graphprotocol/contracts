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
    graph: GraphRuntimeEnvironmentOptions
  }

  export interface HardhatUserConfig {
    graph: GraphRuntimeEnvironmentOptions
  }

  export interface HardhatNetworkConfig {
    addressBooks?: {
      [deployment: string]: string
    }
  }

  export interface HardhatNetworkUserConfig {
    addressBooks?: {
      [deployment: string]: string
    }
  }

  export interface HttpNetworkConfig {
    addressBooks?: {
      [deployment: string]: string
    }
  }

  export interface HttpNetworkUserConfig {
    addressBooks?: {
      [deployment: string]: string
    }
  }

  export interface ProjectPathsConfig {
    graph?: string
  }

  export interface ProjectPathsUserConfig {
    graph?: string
  }
}
