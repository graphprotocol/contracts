import fs from 'fs'
import { BigNumber, utils } from 'ethers'
import { task, types } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { logger } from '../../utils/logging'
import { askForConfirmation, DEFAULT_DEPOSITORS_FILE, DEFAULT_BATCH_SIZE } from './utils'

task('ops:add-to-many', 'Execute a transaction depositing funds to a set of users from a JSON file')
  .addFlag('dryRun', 'Do not execute transaction')
  .addOptionalParam(
    'batchSize',
    'Batch size (i.e. number of users to process at a time)',
    DEFAULT_BATCH_SIZE,
    types.int,
  )
  .addOptionalParam('startBatch', 'Batch number to start from', 0, types.int)
  .addOptionalParam('depositorsFile', 'Path to depositors file', DEFAULT_DEPOSITORS_FILE)
  .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
    const { contracts } = hre
    const accounts = await hre.ethers.getSigners()
    const account = accounts[0]
    const chainId = hre.network.config.chainId

    logger.log(`Getting depositors from ${taskArgs.depositorsFile}...`)
    const depositors = JSON.parse(fs.readFileSync(taskArgs.depositorsFile).toString())
    const users: string[] = depositors.map((depositor) => depositor.address)
    const balances: BigNumber[] = depositors.map((depositor) => BigNumber.from(depositor.balance))

    const totalBalance = balances.reduce((a, b) => a.add(b), BigNumber.from(0))

    logger.log(`Total balance: ${utils.formatEther(totalBalance)}`)
    logger.log(`--------------------------------`)
    for (const depositor of depositors) {
      logger.log(depositor.address, utils.formatEther(depositor.balance.hex))
    }

    const nBatches = Math.floor(depositors.length / taskArgs.batchSize) + 1

    if (taskArgs.startBatch == 0) {
      if (taskArgs.dryRun) {
        logger.log('Dry run, so not executing tx')
        logger.log('Otherwise we would have executed:')
        logger.log(`Token.approve(${contracts.Billing?.address}, ${totalBalance})`)
        logger.log(`On Token contract at ${contracts.Token?.address} on chain ${chainId}`)
        logger.log(`With signer ${account.address}`)

        logger.log('TX calldata:')
        logger.log(`--------------------`)
        const grt = contracts.Token
        if (!grt) {
          throw new Error('GRT contract not found')
        }
        const tx = await grt.populateTransaction.approve(contracts.Billing?.address, totalBalance)
        logger.log(tx.data)
        logger.log(`--------------------`)
      } else if (
        await askForConfirmation(
          `Execute <approve> transaction? **This will execute on network with chain ID ${chainId}**`,
        )
      ) {
        try {
          logger.log('Transactions being sent')
          logger.log(`--------------------`)
          const grt = contracts.Token
          if (!grt) {
            throw new Error('GRT contract not found')
          }
          const tx = await grt.connect(account).approve(contracts.Billing?.address, totalBalance)
          const receipt = await tx.wait()
          logger.log('approve() TX Receipt: ', receipt)
        } catch (e) {
          logger.log(e)
          process.exit(1)
        }
      } else {
        logger.log('Skipping approve tx at user request')
      }
    } else {
      logger.log(`Skipping approve tx since we are not on the first batch`)
    }
    for (let batch = taskArgs.startBatch; batch < nBatches; batch++) {
      const start = batch * taskArgs.batchSize
      const end = Math.min(start + taskArgs.batchSize, depositors.length)
      const batchUsers = users.slice(start, end)
      const batchBalances = balances.slice(start, end)
      logger.log(`Batch ${batch} (${batch + 1}/${nBatches}):`)
      logger.log(`Users: ${batchUsers.length}`)
      logger.log(`Total balance: ${utils.formatEther(batchBalances.reduce((a, b) => a.add(b), BigNumber.from(0)))}`)
      logger.log(`--------------------------------`)
      if (taskArgs.dryRun) {
        logger.log('Dry run, so not executing tx')
        logger.log('Otherwise we would have executed:')
        logger.log(`--------------------`)
        logger.log(`Billing.addToMany([${batchUsers}], [${batchBalances}])`)
        logger.log(`--------------------`)
        logger.log(`On Billing contract at ${contracts.Billing?.address} on chain ${chainId}`)
        logger.log(`With signer ${account.address}`)

        logger.log('TX calldata:')
        logger.log(`--------------------`)
        const billing = contracts.Billing
        if (!billing) {
          throw new Error('Billing contract not found')
        }
        const tx = await billing.populateTransaction.addToMany(batchUsers, batchBalances)
        logger.log(tx.data)
        logger.log(`--------------------`)
      } else if (
        await askForConfirmation(
          `Execute <addToMany> transaction? **This will execute on network with chain ID ${chainId}**`,
        )
      ) {
        try {
          logger.log('Transactions being sent')
          logger.log(`--------------------`)
          const billing = contracts.Billing
          if (!billing) {
            throw new Error('Billing contract not found')
          }
          const tx = await billing.connect(account).addToMany(batchUsers, batchBalances)
          const receipt = await tx.wait()
          logger.log('addToMany TX Receipt: ', receipt)
        } catch (e) {
          logger.log(e)
          process.exit(1)
        }
      } else {
        logger.log('Bye!')
      }

      logger.log(`--------------------------------`)
    }
  })
