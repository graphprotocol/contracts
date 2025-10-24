import type { HardhatEthersProvider } from '@nomicfoundation/hardhat-ethers/internal/hardhat-ethers-provider'
import type { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { ethers } from 'ethers'

// The Graph convention for account derivation is:
// 0: Deployer
// 1: Governor
// 2: Arbitrator
// 3: Pause guardian
// 4: Subgraph Availability Oracle
// 5: Gateway/payer
// 6+: Test accounts

enum GraphAccountIndex {
  Deployer = 0,
  Governor = 1,
  Arbitrator = 2,
  PauseGuardian = 3,
  SubgraphAvailabilityOracle = 4,
  Gateway = 5,
}

export type GraphAccounts = {
  deployer: HardhatEthersSigner | ethers.Signer
  governor: HardhatEthersSigner | ethers.Signer
  arbitrator: HardhatEthersSigner | ethers.Signer
  pauseGuardian: HardhatEthersSigner | ethers.Signer
  subgraphAvailabilityOracle: HardhatEthersSigner | ethers.Signer
  gateway: HardhatEthersSigner | ethers.Signer
  test: (HardhatEthersSigner | ethers.Signer)[]
}

export async function getAccounts(provider: HardhatEthersProvider): Promise<GraphAccounts> {
  return {
    deployer: await getDeployer(provider, GraphAccountIndex.Deployer),
    governor: await getGovernor(provider, GraphAccountIndex.Governor),
    arbitrator: await getArbitrator(provider, GraphAccountIndex.Arbitrator),
    pauseGuardian: await getPauseGuardian(provider, GraphAccountIndex.PauseGuardian),
    subgraphAvailabilityOracle: await getSubgraphAvailabilityOracle(
      provider,
      GraphAccountIndex.SubgraphAvailabilityOracle,
    ),
    gateway: await getGateway(provider, GraphAccountIndex.Gateway),
    test: await getTestAccounts(provider),
  }
}

export async function getDeployer(provider: HardhatEthersProvider, accountIndex = GraphAccountIndex.Deployer) {
  return _getAccount(provider, accountIndex)
}

export async function getGovernor(provider: HardhatEthersProvider, accountIndex = GraphAccountIndex.Governor) {
  return _getAccount(provider, accountIndex)
}

export async function getArbitrator(provider: HardhatEthersProvider, accountIndex = GraphAccountIndex.Arbitrator) {
  return _getAccount(provider, accountIndex)
}

export async function getPauseGuardian(
  provider: HardhatEthersProvider,
  accountIndex = GraphAccountIndex.PauseGuardian,
) {
  return _getAccount(provider, accountIndex)
}

export async function getSubgraphAvailabilityOracle(
  provider: HardhatEthersProvider,
  accountIndex = GraphAccountIndex.SubgraphAvailabilityOracle,
) {
  return _getAccount(provider, accountIndex)
}

export async function getGateway(provider: HardhatEthersProvider, accountIndex = GraphAccountIndex.Gateway) {
  return _getAccount(provider, accountIndex)
}

export async function getTestAccounts(provider: HardhatEthersProvider) {
  const accounts = (await provider.send('eth_accounts', [])) as string[]
  const numReservedAccounts = Object.values(GraphAccountIndex).filter((v) => typeof v === 'number').length
  if (accounts.length < numReservedAccounts) {
    return []
  }
  return await Promise.all(
    accounts.slice(numReservedAccounts).map(async (account) => await _getAccount(provider, account)),
  )
}

async function _getAccount(
  provider: HardhatEthersProvider,
  accountIndex: number | string,
): Promise<HardhatEthersSigner | ethers.Signer> {
  try {
    const accounts = await provider.send('eth_accounts', [])
    if (typeof accountIndex === 'number') {
      if (accounts.length > accountIndex) {
        return provider.getSigner(accountIndex)
      }
    } else if (typeof accountIndex === 'string') {
      if (accounts.includes(accountIndex)) {
        return provider.getSigner(accountIndex)
      }
    }
  } catch {
    // ignore
  }

  // Remote provider fallback
  return new ethers.VoidSigner(
    typeof accountIndex === 'string'
      ? accountIndex
      : ethers.ZeroAddress,
    provider,
  )
}
