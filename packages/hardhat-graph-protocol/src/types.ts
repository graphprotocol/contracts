import { GraphDeploymentsList } from '@graphprotocol/toolshed/deployments'

import type { GraphDeploymentName, GraphDeployments } from '@graphprotocol/toolshed/deployments'
import type { GraphAccounts } from '@graphprotocol/toolshed'
import type { HardhatEthersProvider } from '@nomicfoundation/hardhat-ethers/internal/hardhat-ethers-provider'
import type { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
export type GraphDeploymentOptions = {
  [deployment in GraphDeploymentName]?: string
}

export type GraphRuntimeEnvironmentOptions = {
  deployments?: GraphDeploymentOptions
}

export type GraphRuntimeEnvironment = GraphDeployments & {
  provider: HardhatEthersProvider
  chainId: number
  accounts: {
    getAccounts: () => Promise<GraphAccounts>
    getDeployer: (accountIndex?: number) => Promise<HardhatEthersSigner>
    getGovernor: (accountIndex?: number) => Promise<HardhatEthersSigner>
    getArbitrator: (accountIndex?: number) => Promise<HardhatEthersSigner>
    getPauseGuardian: (accountIndex?: number) => Promise<HardhatEthersSigner>
    getSubgraphAvailabilityOracle: (accountIndex?: number) => Promise<HardhatEthersSigner>
    getGateway: (accountIndex?: number) => Promise<HardhatEthersSigner>
    getTestAccounts: () => Promise<HardhatEthersSigner[]>
  }
}

export function isGraphDeployment(deployment: unknown): deployment is GraphDeploymentName {
  return typeof deployment === 'string' && GraphDeploymentsList.includes(deployment as GraphDeploymentName)
}
