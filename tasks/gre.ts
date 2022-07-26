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

    const getAccounts = async (): Promise<Account[]> => {
      const accounts = []
      const signers: Signer[] = await hre.ethers.getSigners()

      for (const signer of signers) {
        accounts.push({ signer, address: await signer.getAddress() })
      }
      return accounts
    }

    const getNamedAccounts = async (): Promise<NamedAccounts> => {
      const names = [
        'arbitrator',
        'governor',
        'authority',
        'availabilityOracle',
        'pauseGuardian',
        'allocationExchangeOwner',
      ]

      const testAccounts = await getTestAccounts()
      const namedAccounts = names.reduce((acc, name, i) => {
        acc[name] = chainId === '1337' ? testAccounts[i] : getNamedAccount(name)
        return acc
      }, {} as NamedAccounts)

      return namedAccounts
    }

    const getNamedAccount = (name: string): Account => {
      const signer = new VoidSigner(
        getItemValue(readConfig(graphConfigPath, true), `general/${name}`),
      )
      return { signer, address: signer.address }
    }

    // Get accounts from the tail end of the signers list
    // This is to prevent named accounts them from collisioning with test accounts
    const getTestAccounts = async (): Promise<Account[]> => {
      return (await hre.ethers.getSigners()).reverse().map((s) => ({
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
        return (await getAccounts())[0]
      }),
    }
  }
})
