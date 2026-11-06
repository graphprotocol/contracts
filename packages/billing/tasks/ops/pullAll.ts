import fs from 'fs'
import axios from 'axios'

import { BigNumber, utils } from 'ethers'
import { task, types } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { logger } from '../../utils/logging'
import { askForConfirmation, DEFAULT_BILLING_SUBGRAPH, DEFAULT_DEPOSITORS_FILE, DEFAULT_BATCH_SIZE } from './utils'
import path from 'path'

// This script will pull the funds from all the billing accounts and store
// them in a file (by default, `depositors.json` in the same directory as this script).

interface Depositor {
  address: string
  balance: BigNumber
}

export async function getAllDepositors(
  billingSubgraphUrl: string,
  page: number,
  pageSize: number,
  blockNumber: number,
): Promise<Depositor[]> {
  let queryPartOne: string
  if (blockNumber > 0) {
    queryPartOne = `{
      users(
        block: { number: ${blockNumber} },`
  } else {
    queryPartOne = `{
      users(`
  }
  const queryPartTwo = `
      first: ${pageSize},
      skip: ${page * pageSize},
      where: {billingBalance_gt: "0"},
      orderBy: billingBalance,
      orderDirection: desc
    ) {
        id
        billingBalance
      }
    }
  `
  const query = queryPartOne + queryPartTwo
  const response = await axios.post(billingSubgraphUrl, { query })
  logger.log(`Found: ${response.data.data.users.length} users`)
  return response.data.data.users.map((user) => {
    return {
      address: user.id,
      balance: BigNumber.from(user.billingBalance),
    }
  })
}

function writeDepositorsToFile(depositors: Depositor[], filePath: string) {
  let allDepositors: Depositor[] = []
  if (fs.existsSync(filePath)) {
    allDepositors = JSON.parse(fs.readFileSync(filePath).toString())
  }
  allDepositors = allDepositors.concat(depositors)
  fs.writeFileSync(filePath, JSON.stringify(allDepositors, null, 2), { flag: 'w+' })
  const writtenDepositors = JSON.parse(fs.readFileSync(filePath).toString())
  if (writtenDepositors.length != allDepositors.length) {
    throw new Error('Written depositors does not equal fetched depositors')
  }
}

task('ops:pull-all', 'Execute transaction for pulling all funds from users')
  .addFlag('dryRun', 'Do not execute transaction')
  .addOptionalParam('dstAddress', 'Destination address of withdrawal')
  .addOptionalParam(
    'batchSize',
    'Batch size (i.e. number of users to process at a time)',
    DEFAULT_BATCH_SIZE,
    types.int,
  )
  .addOptionalParam('startBatch', 'Batch number to start from', 0, types.int)
  .addOptionalParam('blockNumber', 'Block number to use when fetching balances from the subgraph', 0, types.int)
  .addOptionalParam('depositorsFile', 'Path to EOA depositors file', DEFAULT_DEPOSITORS_FILE)
  .addOptionalParam('billingSubgraphUrl', 'Billing subgraph URL', DEFAULT_BILLING_SUBGRAPH)
  .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
    const accounts = await hre.ethers.getSigners()
    const collector = accounts[0]
    const { contracts } = hre
    const chainId = hre.network.config.chainId
    const dstAddress = taskArgs.dstAddress || collector.address
    let page = taskArgs.startBatch
    const depositorBatches: Depositor[][] = []
    if (!taskArgs.dryRun && taskArgs.startBatch > 0 && taskArgs.blockNumber == 0) {
      logger.log('Please specify a block number when starting from a batch other than 0')
      process.exit(1)
    }
    if (fs.existsSync(taskArgs.depositorsFile) && page == 0) {
      fs.renameSync(taskArgs.depositorsFile, taskArgs.depositorsFile + '.bak')
    }
    let depositors: Depositor[] = []
    do {
      logger.log(`Getting depositors (batch ${page}, size ${taskArgs.batchSize})...`)
      depositors = await getAllDepositors(taskArgs.billingSubgraphUrl, page, taskArgs.batchSize, taskArgs.blockNumber)
      if (depositors.length == 0) {
        logger.log('No depositors found, done with fetching.')
        break
      }

      const balances: BigNumber[] = depositors.map((depositor) => depositor.balance)

      try {
        writeDepositorsToFile(depositors, taskArgs.depositorsFile)
      } catch (e) {
        logger.log(`Error writing depositors file: \n${e}`)
        process.exit(1)
      }

      const totalBalance = balances.reduce((a, b) => a.add(b), BigNumber.from(0))

      logger.log(`Balance: ${utils.formatEther(totalBalance)}`)
      logger.log(`--------------------------------`)
      for (const depositor of depositors) {
        logger.log(depositor.address, utils.formatEther(depositor.balance))
      }
      depositorBatches.push(depositors)
      page += 1
    } while (depositors.length > 0)

    page = 0
    for (const depositors of depositorBatches) {
      if (depositors.length == 0) {
        logger.log('No depositors found, done.')
        break
      }
      logger.log(`Pulling tokens for depositors (batch ${page}, size ${depositors.length})...`)
      const users: string[] = depositors.map((depositor) => depositor.address)
      const balances: BigNumber[] = depositors.map((depositor) => depositor.balance)
      if (taskArgs.dryRun) {
        logger.log('Dry run, so not executing tx')
        logger.log('Otherwise we would have executed:')
        logger.log(`--------------------`)
        logger.log(`Billing.pullMany([${users}], [${balances}], ${dstAddress})`)
        logger.log(`--------------------`)
        logger.log(`On Billing contract at ${contracts.Billing?.address} on chain ${chainId}`)
        logger.log(`With signer ${collector.address}`)

        logger.log('TX calldata:')
        logger.log(`--------------------`)
        const billing = contracts.Billing
        if (!billing) {
          throw new Error('Billing contract not found')
        }
        const tx = await billing.populateTransaction.pullMany(users, balances, dstAddress)
        logger.log(tx.data)
        logger.log(`--------------------`)
      } else if (
        await askForConfirmation(
          `Execute <pullMany> transaction? **This will execute on network with chain ID ${chainId}**`,
        )
      ) {
        logger.log('Transaction being sent')
        logger.log(`--------------------`)
        try {
          const billing = contracts.Billing
          if (!billing) {
            throw new Error('Billing contract not found')
          }
          const tx = await billing.connect(collector).pullMany(users, balances, dstAddress)
          const receipt = await tx.wait()
          logger.log('Receipt: ', receipt)
        } catch (e) {
          logger.log(e)
          process.exit(1)
        }
        logger.log(`--------------------`)
      } else {
        logger.log('Bye!')
      }
      page += 1
    }
  })
