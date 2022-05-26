import { task } from 'hardhat/config'
import * as types from 'hardhat/internal/core/params/argumentTypes'
import { submitSourcesToSourcify } from './sourcify'
import { isFullyQualifiedName, parseFullyQualifiedName } from 'hardhat/utils/contract-names'
import { TASK_COMPILE } from 'hardhat/builtin-tasks/task-names'
import fs from 'fs'

task('sourcify', 'Verifies contract on sourcify')
  .addPositionalParam('address', 'Address of the smart contract to verify', undefined, types.string)
  .addParam('contract', 'Fully qualified name of the contract to verify.', undefined, types.string)
  .setAction(async (args, hre) => {
    if (!isFullyQualifiedName(args.contract)) {
      throw new Error('Invalid fully qualified name of the contract.')
    }

    const { contractName, sourceName: contractSource } = parseFullyQualifiedName(args.contract)

    if (!fs.existsSync(contractSource)) {
      throw new Error(`Contract source ${contractSource} not found.`)
    }

    await hre.run(TASK_COMPILE)
    await submitSourcesToSourcify(hre, {
      source: contractSource,
      name: contractName,
      address: args.address,
      fqn: args.contract,
    })
  })
