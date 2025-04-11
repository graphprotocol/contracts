import type { HardhatEthersProvider } from '@nomicfoundation/hardhat-ethers/internal/hardhat-ethers-provider'
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'

// The Graph convention for account derivation is:
// 0: Deployer
// 1: Governor
// 2: Arbitrator
// 3: Pause guardian
// 4: Subgraph Availability Oracle
// 5: Gateway/payer
// 6+: Test accounts

export type GraphAccounts = {
  deployer: HardhatEthersSigner
  governor: HardhatEthersSigner
  arbitrator: HardhatEthersSigner
  pauseGuardian: HardhatEthersSigner
  subgraphAvailabilityOracle: HardhatEthersSigner
  gateway: HardhatEthersSigner
  test: HardhatEthersSigner[]
}

export async function getAccounts(provider: HardhatEthersProvider): Promise<GraphAccounts> {
  return {
    deployer: await getDeployer(provider),
    governor: await getGovernor(provider),
    arbitrator: await getArbitrator(provider),
    pauseGuardian: await getPauseGuardian(provider),
    subgraphAvailabilityOracle: await getSubgraphAvailabilityOracle(provider),
    gateway: await getGateway(provider),
    test: await getTestAccounts(provider),
  }
}

export async function getDeployer(provider: HardhatEthersProvider, accountIndex = 0) {
  return provider.getSigner(accountIndex)
}

export async function getGovernor(provider: HardhatEthersProvider, accountIndex = 1) {
  return provider.getSigner(accountIndex)
}

export async function getArbitrator(provider: HardhatEthersProvider, accountIndex = 2) {
  return provider.getSigner(accountIndex)
}

export async function getPauseGuardian(provider: HardhatEthersProvider, accountIndex = 3) {
  return provider.getSigner(accountIndex)
}

export async function getSubgraphAvailabilityOracle(provider: HardhatEthersProvider, accountIndex = 4) {
  return provider.getSigner(accountIndex)
}

export async function getGateway(provider: HardhatEthersProvider, accountIndex = 5) {
  return provider.getSigner(accountIndex)
}

export async function getTestAccounts(provider: HardhatEthersProvider) {
  const accounts = await provider.send('eth_accounts', []) as string[]
  if (accounts.length < 6) {
    return []
  }
  return await Promise.all(accounts.slice(6).map(async account => await provider.getSigner(account)))
}
