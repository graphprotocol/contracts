import { task } from 'hardhat/config'
import * as types from 'hardhat/internal/core/params/argumentTypes'
import { submitSourcesToSourcify } from './sourcify'

task('verify:sourcify', 'submit contract source code to sourcify (https://sourcify.dev)')
  .addParam(
    'contractSource',
    'path to the source file of the contract to verify',
    undefined,
    types.string,
  )
  .addOptionalParam(
    'endpoint',
    'endpoint url for sourcify',
    'https://sourcify.dev/server/',
    types.string,
  )
  .addFlag('writeFailingMetadata', 'write to disk failing metadata for easy debugging')
  .setAction(async (args, hre) => {
    const contractName = args.contractSource.split('/').pop().split('.').shift()
    const contract = hre.contracts[contractName]
    const config = {
      endpoint: args.endpoint,
      contract: {
        source: args.contractSource,
        name: contractName,
        address: contract.address,
      },
    }
    await submitSourcesToSourcify(hre, config)
  })
