import { task } from 'hardhat/config'
import * as types from 'hardhat/internal/core/params/argumentTypes'
import { submitSourcesToSourcify } from './sourcify'
import { getAddressBook } from '../../cli/address-book'
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
    const contractName = args.contractSource.split('/').pop().split('.').shift()
    const addressBook = getAddressBook(args.addressBook, chainId)
    const contract = addressBook.getEntry(contractName)

    const config = {
      endpoint: args.sourcifyEndpoint,
      contract: {
        source: args.contractSource,
        name: contractName,
        address: contract.implementation.address,
      },
    }

    console.log('## Verify contract with sourcify ##')
    console.log(`Network: ${hre.network.name}`)
    console.log(`Contract: ${contractName}`)
    console.log(`Address: ${contract.implementation.address}`)

    await submitSourcesToSourcify(hre, config)
  })
