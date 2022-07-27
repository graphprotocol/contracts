import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { extendEnvironment } from 'hardhat/config'
import { lazyFunction, lazyObject } from 'hardhat/plugins'

import { getAddressBook } from '../cli/address-book'
import { loadContracts } from '../cli/contracts'
import { getItemValue, readConfig } from '../cli/config'
import { Account, GREOptions, NamedAccounts } from './type-extensions'
import fs from 'fs'
import { Signer, VoidSigner } from 'ethers'

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

    const getAccounts = async (): Promise<Account[]> => {
      const accounts = []
      const signers: Signer[] = await hre.ethers.getSigners()

      // Skip deployer and named accounts
      for (let i = namedAccountList.length + 1; i < signers.length; i++) {
        accounts.push({ signer: signers[i], address: await signers[i].getAddress() })
      }
      return accounts
    }

    const getNamedAccounts = async (): Promise<NamedAccounts> => {
      const testAccounts = await getTestAccounts()
      const namedAccounts = namedAccountList.reduce((acc, name, i) => {
        acc[name] = chainId === '1337' ? testAccounts[i] : getNamedAccountFromConfig(name)
        return acc
      }, {} as NamedAccounts)

      return namedAccounts
    }

    const getNamedAccountFromConfig = (name: string): Account => {
      const signer = new VoidSigner(
        getItemValue(readConfig(graphConfigPath, true), `general/${name}`),
      )
      return { signer, address: signer.address }
    }

    const getTestAccounts = async (): Promise<Account[]> => {
      // Skip deployer account
      return (await hre.ethers.getSigners()).slice(1).map((s) => ({
        signer: s,
        address: s.address,
      }))
    }

    return {
      addressBook: lazyObject(() => getAddressBook(addressBookPath, chainId)),
      graphConfig: lazyObject(() => readConfig(graphConfigPath, true)),
      contracts: lazyObject(() =>
        loadContracts(getAddressBook(addressBookPath, chainId), hre.ethers.provider),
      ),
      getNamedAccounts: lazyFunction(() => getNamedAccounts),
      getAccounts: lazyFunction(() => getAccounts),
      getDeployer: lazyFunction(() => async () => {
        const signer = hre.ethers.provider.getSigner(0)
        return { signer, address: await signer.getAddress() }
      }),
    }
  }
})
