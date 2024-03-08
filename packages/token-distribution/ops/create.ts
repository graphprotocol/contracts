import PQueue from 'p-queue'
import fs from 'fs'
import consola from 'consola'
import inquirer from 'inquirer'
import { BigNumber, Contract, ContractFactory, ContractReceipt, ContractTransaction, Event, utils } from 'ethers'

import { NonceManager } from '@ethersproject/experimental'
import { task } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { boolean } from 'hardhat/internal/core/params/argumentTypes'
import { TxBuilder } from './tx-builder'

const { getAddress, keccak256, formatEther, parseEther } = utils

const logger = consola.create({})

enum Revocability {
  NotSet,
  Enabled,
  Disabled,
}

interface TokenLockConfigEntry {
  owner?: string
  beneficiary: string
  managedAmount: BigNumber
  startTime: string
  endTime: string
  periods: string
  revocable: Revocability
  releaseStartTime: string
  vestingCliffTime: string
  salt?: string
  txHash?: string
  contractAddress?: string
}

interface TokenLockDeployEntry extends TokenLockConfigEntry {
  contractAddress: string
  salt: string
  txHash: string
}

export const askConfirm = async () => {
  const res = await inquirer.prompt({
    name: 'confirm',
    type: 'confirm',
    message: `Are you sure you want to proceed?`,
  })
  return res.confirm ? res.confirm as boolean : false
}

const isValidAddress = (address: string) => {
  try {
    getAddress(address)
    return true
  } catch (err) {
    logger.error(`Invalid address ${address}`)
    return false
  }
}

export const isValidAddressOrFail = (address: string) => {
  if (!isValidAddress(address)) {
    process.exit(1)
  }
}

const loadDeployData = (filepath: string): TokenLockConfigEntry[] => {
  const data = fs.readFileSync(filepath, 'utf8')
  const entries = data.split('\n').map(e => e.trim())
  entries.shift() // remove the title from the csv
  return entries
    .filter(entryData => !!entryData)
    .map((entryData) => {
      const entry = entryData.split(',')
      return {
        beneficiary: entry[0],
        managedAmount: parseEther(entry[1]),
        startTime: entry[2],
        endTime: entry[3],
        periods: entry[4],
        revocable: parseInt(entry[5]),
        releaseStartTime: entry[6],
        vestingCliffTime: entry[7],
      }
    })
}

const loadResultData = (filepath: string): TokenLockConfigEntry[] => {
  const data = fs.readFileSync(filepath, 'utf8')
  const entries = data.split('\n').map(e => e.trim())
  return entries
    .filter(entryData => !!entryData)
    .map((entryData) => {
      const entry = entryData.split(',')
      return {
        beneficiary: entry[0],
        managedAmount: parseEther(entry[1]),
        startTime: entry[2],
        endTime: entry[3],
        periods: entry[4],
        revocable: parseInt(entry[5]),
        releaseStartTime: entry[6],
        vestingCliffTime: entry[7],
        contractAddress: entry[8],
        salt: entry[9],
        txHash: entry[10],
      }
    })
}

const deployEntryToCSV = (entry: TokenLockDeployEntry) => {
  return [
    entry.beneficiary,
    formatEther(entry.managedAmount),
    entry.startTime,
    entry.endTime,
    entry.periods,
    entry.revocable,
    entry.releaseStartTime,
    entry.vestingCliffTime,
    entry.contractAddress,
    entry.salt,
    entry.txHash,
  ].join(',')
}

const saveDeployResult = (filepath: string, entry: TokenLockDeployEntry) => {
  const line = deployEntryToCSV(entry) + '\n'
  fs.writeFileSync(filepath, line, {
    flag: 'a+',
  })
}

const checkAddresses = (entries: TokenLockConfigEntry[]): boolean => {
  for (const entry of entries) {
    if (!isValidAddress(entry.beneficiary)) {
      return false
    }
  }
  return true
}

const getTotalAmount = (entries: TokenLockConfigEntry[]): BigNumber => {
  return entries.reduce((total, entry) => total.add(entry.managedAmount), BigNumber.from(0))
}

const prettyDate = (date: string) => {
  const n = parseInt(date)
  if (n === 0) return '0'
  const d = new Date(n * 1000)
  return d.toLocaleString()
}

const prettyConfigEntry = (config: TokenLockConfigEntry) => {
  return `
    Beneficiary: ${config.beneficiary}
    Amount: ${formatEther(config.managedAmount)} GRT
    Starts: ${config.startTime} (${prettyDate(config.startTime)})
    Ends: ${config.endTime} (${prettyDate(config.endTime)})
    Periods: ${config.periods}
    Revocable: ${config.revocable}
    ReleaseCliff: ${config.releaseStartTime} (${prettyDate(config.releaseStartTime)})
    VestingCliff: ${config.vestingCliffTime} (${prettyDate(config.vestingCliffTime)})
    Owner: ${config.owner}
    -> ContractAddress: ${config.contractAddress}
  `
}

export const prettyEnv = async (hre: HardhatRuntimeEnvironment) => {
  const { deployer } = await hre.getNamedAccounts()

  const provider = hre.ethers.provider

  const balance = await provider.getBalance(deployer)
  const chainId = (await provider.getNetwork()).chainId
  const nonce = await provider.getTransactionCount(deployer)

  const gas = hre.network.config.gas
  const gasPrice = hre.network.config.gasPrice

  return `
  Wallet: address=${deployer} chain=${chainId} nonce=${nonce} balance=${formatEther(balance)}
  Gas settings: gas=${gas} gasPrice=${gasPrice}
  `
}

const calculateSalt = async (
  hre: HardhatRuntimeEnvironment,
  entry: TokenLockConfigEntry,
  managerAddress: string,
  tokenAddress: string,
) => {
  const factory = await getContractFactory(hre, 'GraphTokenLockWallet')

  return keccak256(
    factory.interface.encodeFunctionData(
      'initialize(address,address,address,address,uint256,uint256,uint256,uint256,uint256,uint256,uint8)',
      [
        managerAddress,
        entry.owner,
        entry.beneficiary,
        tokenAddress,
        entry.managedAmount,
        entry.startTime,
        entry.endTime,
        entry.periods,
        entry.releaseStartTime,
        entry.vestingCliffTime,
        entry.revocable,
      ],
    ),
  )
}

const getContractFactory = async (hre: HardhatRuntimeEnvironment, name: string) => {
  const artifact = await hre.deployments.getArtifact(name)
  return new ContractFactory(artifact.abi, artifact.bytecode)
}

const getDeployContractAddresses = async (entries: TokenLockConfigEntry[], manager: Contract) => {
  const masterCopy = await manager.masterCopy()
  for (const entry of entries) {
    // There are two type of managers
    let contractAddress = ''
    try {
      contractAddress = await manager['getDeploymentAddress(bytes32,address,address)'](
        entry.salt,
        masterCopy,
        manager.address,
      )
    } catch (error) {
      contractAddress = await manager['getDeploymentAddress(bytes32,address)'](entry.salt, masterCopy)
    }

    const deployEntry = { ...entry, salt: entry.salt, txHash: '', contractAddress }
    logger.log(prettyConfigEntry(deployEntry))
  }
}

const populateEntries = async (
  hre: HardhatRuntimeEnvironment,
  entries: TokenLockConfigEntry[],
  managerAddress: string,
  tokenAddress: string,
  ownerAddress: string,
) => {
  const results: TokenLockConfigEntry[] = []
  for (const entry of entries) {
    entry.owner = ownerAddress
    entry.salt = await calculateSalt(hre, entry, managerAddress, tokenAddress)
    results.push(entry)
  }
  return results
}

export const getTokenLockManagerOrFail = async (hre: HardhatRuntimeEnvironment, name: string) => {
  const deployment = await hre.deployments.get(name)
  if (!deployment.address) {
    logger.error('GraphTokenLockManager address not found')
    process.exit(1)
  }

  const manager = await hre.ethers.getContractAt('GraphTokenLockManager', deployment.address)
  try {
    await manager.deployed()
  } catch (err) {
    logger.error('GraphTokenLockManager not deployed at', manager.address)
    process.exit(1)
  }

  return manager
}

export const waitTransaction = async (tx: ContractTransaction, confirmations = 1): Promise<ContractReceipt> => {
  logger.log(`> Transaction sent: ${tx.hash}`)
  const receipt = await tx.wait(confirmations)
  receipt.status ? logger.success(`Transaction succeeded: ${tx.hash}`) : logger.warn(`Transaction failed: ${tx.hash}`)
  return receipt
}

// -- Tasks --

task('create-token-locks', 'Create token lock contracts from file')
  .addParam('deployFile', 'File from where to read the deploy config')
  .addParam('resultFile', 'File where to save results')
  .addParam('ownerAddress', 'Owner address of token lock contracts')
  .addParam('managerName', 'Name of the token lock manager deployment', 'GraphTokenLockManager')
  .addFlag('dryRun', 'Get the deterministic contract addresses but do not deploy')
  .addFlag(
    'txBuilder',
    'Output transaction batch in JSON format, compatible with Gnosis Safe transaction builder. Does not deploy contracts',
  )
  .addOptionalParam('txBuilderTemplate', 'File to use as a template for the transaction builder')
  .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
    // Get contracts
    const manager = await getTokenLockManagerOrFail(hre, taskArgs.managerName)

    // Prepare
    logger.log(await prettyEnv(hre))

    const tokenAddress = await manager.token()

    logger.info('Deploying token lock contracts...')
    logger.log(`> GraphToken: ${tokenAddress}`)
    logger.log(`> GraphTokenLockMasterCopy: ${await manager.masterCopy()}`)
    logger.log(`> GraphTokenLockManager: ${manager.address}`)

    // Load config entries
    logger.log('')
    logger.info('Verifying deployment data...')
    let entries = loadDeployData(taskArgs.deployFile)
    if (!checkAddresses(entries)) {
      process.exit(1)
    }
    logger.success(`Total of ${entries.length} entries. All good!`)

    // Load deployed entries
    const deployedEntries = loadResultData(taskArgs.resultFile)

    // Populate entries
    entries = await populateEntries(hre, entries, manager.address, tokenAddress, taskArgs.ownerAddress)

    // Filter out already deployed ones
    entries = entries.filter(entry => !deployedEntries.find(deployedEntry => deployedEntry.salt === entry.salt))
    logger.success(`Total of ${entries.length} entries after removing already deployed. All good!`)
    if (entries.length === 0) {
      logger.warn('Nothing new to deploy')
      process.exit(1)
    }

    // Dry running
    if (taskArgs.dryRun) {
      logger.info('Running in dry run mode!')
      await getDeployContractAddresses(entries, manager)
      process.exit(0)
    }

    // If deploying contracts, check
    // - deployer is the manager owner
    // - deployer is well funded
    if (!taskArgs.txBuilder) {
      // Ensure deployer is the manager owner
      const tokenLockManagerOwner = await manager.owner()
      const { deployer } = await hre.getNamedAccounts()
      if (tokenLockManagerOwner !== deployer) {
        logger.error('Only the owner can deploy token locks')
        process.exit(1)
      }

      // Check if Manager is funded
      logger.log('')
      logger.info('Verifying balances...')
      const grt = await hre.ethers.getContractAt('ERC20', tokenAddress)
      const totalAmount = getTotalAmount(entries)
      const currentBalance = await grt.balanceOf(manager.address)
      logger.log(`> Amount to distribute:  ${formatEther(totalAmount)} GRT`)
      logger.log(`> Amount in the Manager: ${formatEther(currentBalance)} GRT`)
      if (currentBalance.lt(totalAmount)) {
        logger.error(`GraphTokenLockManager is underfunded. Deposit more funds into ${manager.address}`)
        process.exit(1)
      }
      logger.success('Manager has enough tokens to fund contracts')
    }

    // Summary
    if (!(await askConfirm())) {
      logger.log('Cancelled')
      process.exit(1)
    }

    if (!taskArgs.txBuilder) {
      // Deploy contracts
      const accounts = await hre.ethers.getSigners()
      const nonceManager = new NonceManager(accounts[0]) // Use NonceManager to send concurrent txs

      const queue = new PQueue({ concurrency: 6 })

      for (const entry of entries) {
        await queue.add(async () => {
          logger.log('')
          logger.info(`Creating contract...`)
          logger.log(prettyConfigEntry(entry))

          try {
            // Deploy
            const tx = await manager
              .connect(nonceManager)
              .createTokenLockWallet(
                entry.owner,
                entry.beneficiary,
                entry.managedAmount,
                entry.startTime,
                entry.endTime,
                entry.periods,
                entry.releaseStartTime,
                entry.vestingCliffTime,
                entry.revocable,
              )
            const receipt = await waitTransaction(tx)
            const event: Event = receipt.events[0]
            const contractAddress = event.args['proxy']
            logger.success(`Deployed: ${contractAddress} (${entry.salt})`)

            // Save result
            const deployResult = { ...entry, salt: entry.salt, txHash: tx.hash, contractAddress }
            saveDeployResult(taskArgs.resultFile, deployResult)
          } catch (err) {
            logger.error(err)
          }
        })
      }
      await queue.onIdle()
    } else {
      // Output tx builder json
      logger.info(`Creating transaction builder JSON file...`)
      const chainId = (await hre.ethers.provider.getNetwork()).chainId.toString()
      const txBuilder = new TxBuilder(chainId, taskArgs.txBuilderTemplate)

      // Send funds to the manager
      const grt = await hre.ethers.getContractAt('ERC20', tokenAddress)
      const totalAmount = getTotalAmount(entries)
      const currentBalance = await grt.balanceOf(manager.address)
      if (currentBalance.lt(totalAmount)) {
        logger.log('Building manager funding transactions...')
        const remainingBalance = totalAmount.sub(currentBalance)
        // Use GRT.approve + the manager deposit function instead of GRT.transfer to be super safe
        const approveTx = await grt.populateTransaction.approve(manager.address, remainingBalance)
        txBuilder.addTx({
          to: tokenAddress,
          value: '0',
          data: approveTx.data,
        })
        const depositTx = await manager.populateTransaction.deposit(remainingBalance)
        txBuilder.addTx({
          to: manager.address,
          value: '0',
          data: depositTx.data,
        })
      }

      for (const entry of entries) {
        logger.log('Building tx...')
        logger.log(prettyConfigEntry(entry))
        const tx = await manager.populateTransaction.createTokenLockWallet(
          entry.owner,
          entry.beneficiary,
          entry.managedAmount,
          entry.startTime,
          entry.endTime,
          entry.periods,
          entry.releaseStartTime,
          entry.vestingCliffTime,
          entry.revocable,
        )
        txBuilder.addTx({
          to: manager.address,
          value: '0',
          data: tx.data,
        })
      }

      // Save result into json file
      const outputFile = txBuilder.saveToFile()
      logger.success(`Transaction batch saved to ${outputFile}`)
    }
  })

task('create-token-locks-simple', 'Create token lock contracts from file')
  .addParam('deployFile', 'File from where to read the deploy config')
  .addParam('resultFile', 'File where to save results')
  .addParam('tokenAddress', 'Token address to use in the contracts')
  .addParam('ownerAddress', 'Owner address of token lock contracts')
  .addOptionalParam('dryRun', 'Get the deterministic contract addresses but do not deploy', false, boolean)
  .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
    // Prepare
    logger.log(await prettyEnv(hre))

    // Validations
    const tokenAddress = taskArgs.tokenAddress
    const ownerAddress = taskArgs.ownerAddress
    isValidAddressOrFail(tokenAddress)
    isValidAddressOrFail(ownerAddress)

    logger.info('Deploying token lock simple contracts...')
    logger.log(`> GraphToken: ${tokenAddress}`)

    // Load config entries
    logger.log('')
    logger.info('Verifying deployment data...')
    const entries = loadDeployData(taskArgs.deployFile)
    if (!checkAddresses(entries)) {
      process.exit(1)
    }
    logger.success(`Total of ${entries.length} entries. All good!`)

    // Check if Manager is funded
    logger.log('')
    logger.info('Verifying balances...')
    const totalAmount = getTotalAmount(entries)
    logger.log(`> Amount to distribute:  ${formatEther(totalAmount)} GRT`)

    // Summary
    if (!(await askConfirm())) {
      logger.log('Cancelled')
      process.exit(1)
    }

    // Get accounts
    const accounts = await hre.ethers.getSigners()
    const deployer = accounts[0]

    // Deploy contracts
    for (const entry of entries) {
      logger.log('')
      logger.info(`Creating contract...`)
      logger.log(prettyConfigEntry(entry))

      try {
        const tokenLockSimpleFactory = await getContractFactory(hre, 'GraphTokenLockSimple')
        const tokenLockSimpleDeployment = await tokenLockSimpleFactory.connect(deployer).deploy()
        const tokenLockSimple = await tokenLockSimpleDeployment.deployed()
        logger.success(`Deployed: ${tokenLockSimple.address}`)

        logger.log('Setting up...')
        const tx = await tokenLockSimple.initialize(
          ownerAddress,
          entry.beneficiary,
          tokenAddress,
          entry.managedAmount,
          entry.startTime,
          entry.endTime,
          entry.periods,
          entry.releaseStartTime,
          entry.vestingCliffTime,
          entry.revocable,
        )
        await waitTransaction(tx)

        // Save result
        const deployResult = { ...entry, txHash: tx.hash, salt: '', contractAddress: tokenLockSimple.address }
        saveDeployResult(taskArgs.resultFile, deployResult)
      } catch (err) {
        logger.log(err)
      }
    }
  })

task('scan-token-locks-balances', 'Check current balances of deployed contracts')
  .addParam('resultFile', 'File where to load deployed contracts')
  .addParam('managerName', 'Name of the token lock manager deployment', 'GraphTokenLockManager')
  .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
    // Get contracts
    const manager = await getTokenLockManagerOrFail(hre, taskArgs.managerName)

    // Prepare
    logger.log(await prettyEnv(hre))

    const tokenAddress = await manager.token()

    logger.info('Using:')
    logger.log(`> GraphToken: ${tokenAddress}`)
    logger.log(`> GraphTokenLockMasterCopy: ${await manager.masterCopy()}`)
    logger.log(`> GraphTokenLockManager: ${manager.address}`)

    const grt = await hre.ethers.getContractAt('ERC20', tokenAddress)
    const balance = await grt.balanceOf(manager.address)
    logger.log('Current Manager balance is ', formatEther(balance))

    // Load deployed entries
    const deployedEntries = loadResultData('/' + taskArgs.resultFile)

    let balances = BigNumber.from(0)
    for (const entry of deployedEntries) {
      balances = balances.add(await grt.balanceOf(entry.contractAddress))
    }
    logger.log(deployedEntries.length)
    logger.log(formatEther(balances))
  })
