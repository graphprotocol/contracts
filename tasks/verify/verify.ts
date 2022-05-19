import { task } from 'hardhat/config'
import * as types from 'hardhat/internal/core/params/argumentTypes'
import { submitSourcesToSourcify } from './sourcify'
import { AddressBook, getAddressBook } from '../../cli/address-book'
import { cliOpts } from '../../cli/defaults'

task('verify:sourcify', 'submit contract source code to sourcify (https://sourcify.dev)')
  .addParam(
    'contractSource',
    'Path to the source file of the contract to verify.',
    undefined,
    types.string,
  )
  .addOptionalParam(
    'sourcifyEndpoint',
    "Sourcify's endpoint url.",
    'https://sourcify.dev/server/',
    types.string,
  )
  .addParam('addressBook', cliOpts.addressBook.description, cliOpts.addressBook.default)
  .setAction(async (args, hre) => {
    const chainId = hre.network.config.chainId.toString()

    const contractName = getContractName(args.contractSource)
    const contractAddress = getContractAddress(args.addressBook, contractName, chainId)
    const config = {
      endpoint: args.sourcifyEndpoint,
      contract: {
        source: args.contractSource,
        name: contractName,
        address: contractAddress,
      },
    }

    console.log('## Verify contract with sourcify ##')
    console.log(`Network: ${hre.network.name}`)
    console.log(`Contract: ${contractName}`)
    console.log(`Address: ${contractAddress}`)

    await submitSourcesToSourcify(hre, config)
  })

const getContractName = (contractSource: string): string => {
  return contractSource.split('/').pop().split('.').shift()
}

const getContractAddress = (addressBookPath: string, contractName: string, chainId: string) => {
  const addressBook = getAddressBook(addressBookPath, chainId)
  const contract = addressBook.getEntry(contractName)

  if (contract === undefined) {
    throw new Error(`Contract ${contractName} not found in address book.`)
  }

  if (contract.implementation?.address === undefined) {
    throw new Error(`Contract ${contractName} has no implementation address.`)
  }

  return contract.implementation.address
}
