import { setGRTBalance } from '../hardhat'
import { toBeHex } from 'ethers'

import type { Addressable } from 'ethers'
import type { HardhatEthersProvider } from '@nomicfoundation/hardhat-ethers/internal/hardhat-ethers-provider'
import type { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'

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
  deployer: HardhatEthersSigner
  governor: HardhatEthersSigner
  arbitrator: HardhatEthersSigner
  pauseGuardian: HardhatEthersSigner
  subgraphAvailabilityOracle: HardhatEthersSigner
  gateway: HardhatEthersSigner
  test: HardhatEthersSigner[]
}

export async function getAccounts(provider: HardhatEthersProvider, grtTokenAddress?: string | Addressable): Promise<GraphAccounts> {
  return {
    deployer: await getDeployer(provider, GraphAccountIndex.Deployer, grtTokenAddress),
    governor: await getGovernor(provider, GraphAccountIndex.Governor, grtTokenAddress),
    arbitrator: await getArbitrator(provider, GraphAccountIndex.Arbitrator, grtTokenAddress),
    pauseGuardian: await getPauseGuardian(provider, GraphAccountIndex.PauseGuardian, grtTokenAddress),
    subgraphAvailabilityOracle: await getSubgraphAvailabilityOracle(provider, GraphAccountIndex.SubgraphAvailabilityOracle, grtTokenAddress),
    gateway: await getGateway(provider, GraphAccountIndex.Gateway, grtTokenAddress),
    test: await getTestAccounts(provider, grtTokenAddress),
  }
}

export async function getDeployer(provider: HardhatEthersProvider, accountIndex = GraphAccountIndex.Deployer, grtTokenAddress?: string | Addressable) {
  return _getAccount(provider, accountIndex, grtTokenAddress)
}

export async function getGovernor(provider: HardhatEthersProvider, accountIndex = GraphAccountIndex.Governor, grtTokenAddress?: string | Addressable) {
  return _getAccount(provider, accountIndex, grtTokenAddress)
}

export async function getArbitrator(provider: HardhatEthersProvider, accountIndex = GraphAccountIndex.Arbitrator, grtTokenAddress?: string | Addressable) {
  return _getAccount(provider, accountIndex, grtTokenAddress)
}

export async function getPauseGuardian(provider: HardhatEthersProvider, accountIndex = GraphAccountIndex.PauseGuardian, grtTokenAddress?: string | Addressable) {
  return _getAccount(provider, accountIndex, grtTokenAddress)
}

export async function getSubgraphAvailabilityOracle(provider: HardhatEthersProvider, accountIndex = GraphAccountIndex.SubgraphAvailabilityOracle, grtTokenAddress?: string | Addressable) {
  return _getAccount(provider, accountIndex, grtTokenAddress)
}

export async function getGateway(provider: HardhatEthersProvider, accountIndex = GraphAccountIndex.Gateway, grtTokenAddress?: string | Addressable) {
  return _getAccount(provider, accountIndex, grtTokenAddress)
}

export async function getTestAccounts(provider: HardhatEthersProvider, grtTokenAddress?: string | Addressable) {
  const accounts = await provider.send('eth_accounts', []) as string[]
  const numReservedAccounts = Object.values(GraphAccountIndex).filter(v => typeof v === 'number').length
  if (accounts.length < numReservedAccounts) {
    return []
  }
  return await Promise.all(
    accounts
      .slice(numReservedAccounts)
      .map(async account => await _getAccount(provider, account, grtTokenAddress)),
  )
}

async function _getAccount(provider: HardhatEthersProvider, accountIndex: number | string, grtTokenAddress?: string | Addressable) {
  const account = await provider.getSigner(accountIndex)

  // If the chain is local, send 10M GRT to the account
  const chainId = await provider.send('eth_chainId', []) as string
  const isLocal = [toBeHex(1337), toBeHex(31337)].includes(toBeHex(BigInt(chainId)))
  if (grtTokenAddress && isLocal) {
    await setGRTBalance(provider, grtTokenAddress, account.address, 10_000_000n)
  }

  return account
}
