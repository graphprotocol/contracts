import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { extendEnvironment } from 'hardhat/config'
import { lazyObject } from 'hardhat/plugins'

import { getAddressBook } from '../utils/addressBook'
import { BillingContracts, loadContracts } from '../utils/contracts'

declare module 'hardhat/types/runtime' {
  export interface HardhatRuntimeEnvironment {
    contracts: BillingContracts
  }
}

extendEnvironment((hre: HardhatRuntimeEnvironment) => {
  const chainId = (hre.network.config.chainId as number).toString()
  const addressBookPath = process.env.ADDRESS_BOOK || 'addresses.json'
  const addresses = getAddressBook(addressBookPath, chainId)
  const addressBook = addresses[chainId as unknown as number]
  hre['contracts'] = lazyObject(() => {
    return loadContracts(
      addressBook?.Billing,
      addressBook?.BillingConnector,
      addressBook?.GraphToken ?? addressBook?.L2GraphToken,
      addressBook?.BanxaWrapper,
      hre.ethers.provider,
    )
  })
})
