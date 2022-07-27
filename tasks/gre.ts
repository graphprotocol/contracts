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

    const getTestAccounts = async (): Promise<Account[]> => {
      const accounts = []
      const signers: Signer[] = await hre.ethers.getSigners()

      // Skip deployer and named accounts
      for (let i = namedAccountList.length + 1; i < signers.length; i++) {
        accounts.push({ signer: signers[i], address: await signers[i].getAddress() })
      }
      return accounts
    }

    // Returns void signers. Upgrades to signer on loca networks.
    const getNamedAccounts = async (): Promise<NamedAccounts> => {
      const namedAccounts = namedAccountList.reduce((acc, name) => {
        const address = getItemValue(readConfig(graphConfigPath, true), `general/${name}`)

        if (chainId === '1337') {
          const signer = hre.ethers.provider.getSigner(address)
          acc[name] = { signer, address: address }
        } else {
          const signer = new VoidSigner(address)
          acc[name] = { signer, address: signer.address }
        }

        return acc
      }, {} as NamedAccounts)

      return namedAccounts
    }

    return {
      addressBook: lazyObject(() => getAddressBook(addressBookPath, chainId)),
      graphConfig: lazyObject(() => readConfig(graphConfigPath, true)),
      contracts: lazyObject(() =>
        loadContracts(getAddressBook(addressBookPath, chainId), hre.ethers.provider),
      ),
      getNamedAccounts: lazyFunction(() => getNamedAccounts),
      getTestAccounts: lazyFunction(() => getTestAccounts),
      getDeployer: lazyFunction(() => async () => {
        const signer = hre.ethers.provider.getSigner(0)
        return { signer, address: await signer.getAddress() }
      }),
    }
  }
})
