import { task } from 'hardhat/config'
import * as types from 'hardhat/internal/core/params/argumentTypes'
import { submitSourcesToSourcify } from './sourcify'
import { isFullyQualifiedName, parseFullyQualifiedName } from 'hardhat/utils/contract-names'
import { TASK_COMPILE } from 'hardhat/builtin-tasks/task-names'
import { getAddressBook } from '../../cli/address-book'
import { cliOpts } from '../../cli/defaults'
import fs from 'fs'
import path from 'path'

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

task('sourcifyAll', 'Verifies all contracts on sourcify')
  .addParam('addressBook', cliOpts.addressBook.description, cliOpts.addressBook.default)
  .setAction(async (_args, hre) => {
    const chainId = hre.network.config.chainId
    const chainName = hre.network.name

    if (!chainId || !chainName) {
      throw new Error('Cannot verify contracts without a network')
    }
    console.log(`> Verifying all contracts on chain ${chainName}[${chainId}]...`)
    const addressBook = getAddressBook(cliOpts.addressBook.default, chainId.toString())

    for (const contractName of addressBook.listEntries()) {
      console.log(`\n> Verifying contract ${contractName}...`)

      const contractPath = getContractPath(contractName)
      if (contractPath) {
        const contract = addressBook.getEntry(contractName)
        if (contract.implementation) {
          console.log('Contract is upgradeable, verifying proxy...')

          await hre.run('sourcify', {
            address: contract.address,
            contract: 'contracts/upgrades/GraphProxy.sol:GraphProxy',
          })
        }

        // Verify implementation
        await hre.run('sourcify', {
          address: contract.implementation?.address ?? contract.address,
          contract: `${contractPath}:${contractName}`,
        })
      } else {
        console.log(`Contract ${contractName} not found.`)
      }
    }
  })

function getContractPath(contract: string): string | undefined {
  const files = readDirRecursive('contracts/')
  return files.find((f) => path.basename(f) === `${contract}.sol`)
}

function readDirRecursive(dir: string, allFiles: string[] = []) {
  const files = fs.readdirSync(dir)

  for (const file of files) {
    if (fs.statSync(path.join(dir, file)).isDirectory()) {
      allFiles = readDirRecursive(path.join(dir, file), allFiles)
    } else {
      allFiles.push(path.join(dir, file))
    }
  }

  return allFiles
}
