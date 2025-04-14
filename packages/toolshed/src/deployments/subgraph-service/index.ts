import { HardhatEthersProvider } from '@nomicfoundation/hardhat-ethers/internal/hardhat-ethers-provider'
import { SubgraphServiceAddressBook } from './address-book'

export { SubgraphServiceAddressBook }
export type { SubgraphServiceContractName, SubgraphServiceContracts } from './contracts'

export function loadSubgraphService(addressBookPath: string, chainId: number, provider: HardhatEthersProvider) {
  const addressBook = new SubgraphServiceAddressBook(addressBookPath, chainId)
  return {
    addressBook: addressBook,
    contracts: addressBook.loadContracts(provider),
  }
}
