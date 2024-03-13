import { EthersProviderWrapper } from '@nomiclabs/hardhat-ethers/internal/ethers-provider-wrapper'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { derivePrivateKeys } from 'hardhat/internal/core/providers/util'
import { Wallet } from 'ethers'
import { getItemValue, readConfig } from '..'
import { getNetworkName } from './helpers/network'
import { HttpNetworkHDAccountsConfig, NetworksConfig } from 'hardhat/types'
import { GREPluginError } from './helpers/error'

import type { AccountNames, NamedAccounts } from './types'

const namedAccountList: AccountNames[] = [
  'arbitrator',
  'governor',
  'authority',
  'availabilityOracle',
  'pauseGuardian',
  'allocationExchangeOwner',
]

export async function getNamedAccounts(
  provider: EthersProviderWrapper,
  graphConfigPath: string,
): Promise<NamedAccounts> {
  const namedAccounts = namedAccountList.reduce(
    async (accountsPromise, name) => {
      const accounts = await accountsPromise
      const address = getItemValue(readConfig(graphConfigPath, true), `general/${name}`)
      accounts[name] = await SignerWithAddress.create(provider.getSigner(address))
      return accounts
    },
    Promise.resolve({} as NamedAccounts),
  )

  return namedAccounts
}

export async function getDeployer(provider: EthersProviderWrapper): Promise<SignerWithAddress> {
  const signer = provider.getSigner(0)
  return SignerWithAddress.create(signer)
}

export async function getTestAccounts(
  provider: EthersProviderWrapper,
  graphConfigPath: string,
): Promise<SignerWithAddress[]> {
  // Get list of privileged accounts we don't want as test accounts
  const namedAccounts = await getNamedAccounts(provider, graphConfigPath)
  const blacklist = namedAccountList.map((a) => {
    const account = namedAccounts[a]
    return account.address
  })
  blacklist.push((await getDeployer(provider)).address)

  // Get signers and filter out blacklisted accounts
  const accounts = await provider.listAccounts()
  const signers = await Promise.all(
    accounts.map(async (account) => await SignerWithAddress.create(provider.getSigner(account))),
  )

  return signers.filter((s) => {
    return !blacklist.includes(s.address)
  })
}

export async function getAllAccounts(
  provider: EthersProviderWrapper,
): Promise<SignerWithAddress[]> {
  const accounts = await provider.listAccounts()
  return await Promise.all(
    accounts.map(async (account) => await SignerWithAddress.create(provider.getSigner(account))),
  )
}

export async function getWallets(
  networks: NetworksConfig,
  chainId: number,
  mainNetworkName: string,
): Promise<Wallet[]> {
  const networkName = getNetworkName(networks, chainId, mainNetworkName)
  if (networkName === undefined) {
    throw new GREPluginError(`Could not find networkName for chainId: ${chainId}!`)
  }
  const accounts = networks[networkName].accounts
  const mnemonic = (accounts as HttpNetworkHDAccountsConfig).mnemonic

  if (mnemonic) {
    const privateKeys = derivePrivateKeys(mnemonic, "m/44'/60'/0'/0/", 0, 20, '')
    return privateKeys.map((privateKey) => new Wallet(privateKey))
  }

  return []
}

export async function getWallet(
  networks: NetworksConfig,
  chainId: number,
  mainNetworkName: string,
  address: string,
): Promise<Wallet> {
  const wallets = await getWallets(networks, chainId, mainNetworkName)
  const found = wallets.find((w) => w.address === address)
  if (found === undefined) {
    throw new GREPluginError(`Could not find wallet for address: ${address}!`)
  }
  return found
}
