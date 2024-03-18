import { task } from 'hardhat/config'
import * as types from 'hardhat/internal/core/params/argumentTypes'
import { submitSourcesToSourcify } from './sourcify'
import { isFullyQualifiedName, parseFullyQualifiedName } from 'hardhat/utils/contract-names'
import { TASK_COMPILE } from 'hardhat/builtin-tasks/task-names'
import { greTask } from '@graphprotocol/sdk/gre'
import fs from 'fs'
import path from 'path'
import { HardhatRuntimeEnvironment } from 'hardhat/types/runtime'
import { getContractConfig, readConfig } from '@graphprotocol/sdk'

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

greTask('sourcifyAll', 'Verifies all contracts on sourcify').setAction(async (_args, hre) => {
  const chainId = hre.network.config.chainId
  const chainName = hre.network.name

  if (!chainId || !chainName) {
    throw new Error('Cannot verify contracts without a network')
  }
  console.log(`> Verifying all contracts on chain ${chainName}[${chainId}]...`)
  const { addressBook } = hre.graph({ addressBook: _args.addressBook })

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

greTask('verifyAll', 'Verifies all contracts on etherscan').setAction(async (args, hre) => {
  const chainId = hre.network.config.chainId
  const chainName = hre.network.name

  if (!chainId || !chainName) {
    throw new Error('Cannot verify contracts without a network')
  }

  console.log(`> Verifying all contracts on chain ${chainName}[${chainId}]...`)
  const { addressBook, getDeployer } = hre.graph({
    addressBook: args.addressBook,
    graphConfig: args.graphConfig,
  })
  const graphConfig = readConfig(args.graphConfig, false)
  const deployer = (await getDeployer()).address
  for (const contractName of addressBook.listEntries()) {
    console.log(`\n> Verifying contract ${contractName}...`)

    const contractConfig = getContractConfig(graphConfig, addressBook, contractName, deployer)
    const contractPath = getContractPath(contractName)
    const constructorParams = contractConfig.params.map(p => p.value.toString())

    if (contractPath) {
      const contract = addressBook.getEntry(contractName)

      if (contract.implementation) {
        console.log('Contract is upgradeable, verifying proxy...')
        const proxyAdmin = addressBook.getEntry('GraphProxyAdmin')

        // Verify proxy
        await safeVerify(hre, {
          address: contract.address,
          contract: 'contracts/upgrades/GraphProxy.sol:GraphProxy',
          constructorArgsParams: [contract.implementation.address, proxyAdmin.address],
        })
      }

      // Verify implementation
      console.log('Verifying implementation...')
      await safeVerify(hre, {
        address: contract.implementation?.address ?? contract.address,
        contract: `${contractPath}:${contractName}`,
        constructorArgsParams: contract.implementation ? [] : constructorParams,
      })
    } else {
      console.log(`Contract ${contractName} not found.`)
    }
  }
})

// etherscan API throws errors if the contract is already verified
async function safeVerify(hre: HardhatRuntimeEnvironment, taskArguments: unknown): Promise<void> {
  try {
    await hre.run('verify', taskArguments)
  } catch (error) {
    console.log(error.message)
  }
}

function getContractPath(contract: string): string | undefined {
  const files = readDirRecursive('contracts/')
  return files.find(f => path.basename(f) === `${contract}.sol`)
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
