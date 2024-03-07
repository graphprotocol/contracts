import { task } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { askConfirm, prettyEnv, waitTransaction } from './create'
import consola from 'consola'
import { TxBuilder } from './tx-builder'

const logger = consola.create({})

const getTokenLockWalletOrFail = async (hre: HardhatRuntimeEnvironment, address: string) => {
  const wallet = await hre.ethers.getContractAt('GraphTokenLockWallet', address)
  try {
    await wallet.deployed()
  } catch (err) {
    logger.error('GraphTokenLockWallet not deployed at', wallet.address)
    process.exit(1)
  }

  return wallet
}

task('cancel-token-lock', 'Cancel token lock contract')
  .addParam('contract', 'Address of the vesting contract to be cancelled')
  .addFlag('dryRun', 'Get the deterministic contract addresses but do not deploy')
  .addFlag(
    'txBuilder',
    'Output transaction batch in JSON format, compatible with Gnosis Safe transaction builder. Does not deploy contracts',
  )
  .addOptionalParam('txBuilderTemplate', 'File to use as a template for the transaction builder')
  .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
    // Get contracts
    const lockWallet = await getTokenLockWalletOrFail(hre, taskArgs.contract)

    // Prepare
    logger.log(await prettyEnv(hre))

    logger.info('Cancelling token lock contract...')
    logger.log(`> GraphTokenLockWallet: ${lockWallet.address}`)

    // Check lock status
    logger.log('Veryfing lock status...')
    const lockAccepted = await lockWallet.isAccepted()
    if (lockAccepted) {
      logger.error('Lock was already accepted, use revoke() to revoke the vesting schedule')
      process.exit(1)
    } else {
      logger.success(`Lock not accepted yet, preparing to cancel!`)
    }

    // Nothing else to do, exit if dry run
    if (taskArgs.dryRun) {
      logger.info('Running in dry run mode!')
      process.exit(0)
    }

    if (!(await askConfirm())) {
      logger.log('Cancelled')
      process.exit(1)
    }

    if (!taskArgs.txBuilder) {
      const { deployer } = await hre.getNamedAccounts()
      const lockOwner = await lockWallet.owner()
      if (lockOwner !== deployer) {
        logger.error('Only the owner can cancell the token lock')
        process.exit(1)
      }

      logger.info(`Cancelling contract...`)
      const tx = await lockWallet.cancelLock()
      await waitTransaction(tx)
      logger.success(`Token lock at ${lockWallet.address} was cancelled`)
    } else {
      logger.info(`Creating transaction builder JSON file...`)
      const chainId = (await hre.ethers.provider.getNetwork()).chainId.toString()
      const txBuilder = new TxBuilder(chainId, taskArgs.txBuilderTemplate)

      const tx = await lockWallet.populateTransaction.cancelLock()
      txBuilder.addTx({
        to: lockWallet.address,
        data: tx.data,
        value: 0,
      })

      // Save result into json file
      const outputFile = txBuilder.saveToFile()
      logger.success(`Transaction saved to ${outputFile}`)
    }
  })
