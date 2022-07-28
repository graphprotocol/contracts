import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { extendEnvironment } from 'hardhat/config'
import { lazyFunction, lazyObject } from 'hardhat/plugins'

import { getAddressBook } from '../cli/address-book'
import { loadContracts } from '../cli/contracts'
import { getItemValue, readConfig } from '../cli/config'
import { GREOptions, NamedAccounts } from './type-extensions'
import fs from 'fs'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

// Graph Runtime Environment (GRE) extensions for the HRE
extendEnvironment((hre: HardhatRuntimeEnvironment) => {
  hre.graph = (opts: GREOptions = {}) => {
    const chainId = hre.network.config.chainId?.toString() ?? '1337'
    const addressBookPath = opts.addressBook ?? process.env.ADDRESS_BOOK
    const graphConfigPath = opts.graphConfig ?? process.env.GRAPH_CONFIG

    if (!fs.existsSync(addressBookPath)) {
      throw new Error(`Address book not found: ${addressBookPath}`)
    }

    if (!fs.existsSync(graphConfigPath)) {
      throw new Error(`Graph config not found: ${graphConfigPath}`)
    }

    const namedAccountList = [
      'arbitrator',
      'governor',
      'authority',
      'availabilityOracle',
      'pauseGuardian',
      'allocationExchangeOwner',
    ]

    const getTestAccounts = async (): Promise<SignerWithAddress[]> => {
      // Get list of privileged accounts we don't want as test accounts
      const namedAccounts = await getNamedAccounts()
      const blacklist = namedAccountList.map((a) => {
        const account = namedAccounts[a] as SignerWithAddress
        return account.address
      })
      blacklist.push((await getDeployer()).address)

      // Get signers and filter out blacklisted accounts
      let signers: SignerWithAddress[] = await hre.ethers.getSigners()
      signers = signers.filter((s) => {
        return !blacklist.includes(s.address)
      })

      return signers
    }

    const getNamedAccounts = async (): Promise<NamedAccounts> => {
      const namedAccounts = namedAccountList.reduce(async (accP, name) => {
        const acc = await accP
        const address = getItemValue(readConfig(graphConfigPath, true), `general/${name}`)
        acc[name] = await hre.ethers.getSigner(address)
        return acc
      }, Promise.resolve({} as NamedAccounts))

      return namedAccounts
    }

    const getDeployer = async () => {
      const signer = hre.ethers.provider.getSigner(0)
      return hre.ethers.getSigner(await signer.getAddress())
    }

    return {
      addressBook: lazyObject(() => getAddressBook(addressBookPath, chainId)),
      graphConfig: lazyObject(() => readConfig(graphConfigPath, true)),
      contracts: lazyObject(() =>
        loadContracts(getAddressBook(addressBookPath, chainId), hre.ethers.provider),
      ),
      getNamedAccounts: lazyFunction(() => getNamedAccounts),
      getTestAccounts: lazyFunction(() => getTestAccounts),
      getDeployer: lazyFunction(() => getDeployer),
    }
  }
})
