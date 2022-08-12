import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { providers } from 'ethers'
import { getItemValue, readConfig } from '../cli/config'
import { AccountNames, NamedAccounts } from './type-extensions'

const namedAccountList: AccountNames[] = [
  'arbitrator',
  'governor',
  'authority',
  'availabilityOracle',
  'pauseGuardian',
  'allocationExchangeOwner',
]

export async function getNamedAccounts(
  provider: providers.JsonRpcProvider,
  graphConfigPath: string,
): Promise<NamedAccounts> {
  const namedAccounts = namedAccountList.reduce(async (accountsPromise, name) => {
    const accounts = await accountsPromise
    const address = getItemValue(readConfig(graphConfigPath, true), `general/${name}`)
    accounts[name] = await SignerWithAddress.create(provider.getSigner(address))
    return accounts
  }, Promise.resolve({} as NamedAccounts))

  return namedAccounts
}

export async function getDeployer(provider: providers.JsonRpcProvider): Promise<SignerWithAddress> {
  const signer = provider.getSigner(0)
  return SignerWithAddress.create(signer)
}

export async function getTestAccounts(
  provider: providers.JsonRpcProvider,
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
