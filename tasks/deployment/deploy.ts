import { Wallet } from 'ethers'
import { task } from 'hardhat/config'

import { loadEnv } from '../../cli/env'
import { cliOpts } from '../../cli/defaults'
import { migrate } from '../../cli/commands/migrate'

task('migrate', 'Migrate contracts')
  .addParam('addressBook', cliOpts.addressBook.description, cliOpts.addressBook.default)
  .addParam('graphConfig', cliOpts.graphConfig.description, cliOpts.graphConfig.default)
  .addFlag('skipConfirmation', cliOpts.skipConfirmation.description)
  .addFlag('force', cliOpts.force.description)
  .addFlag('autoMine', 'Enable auto mining after deployment on local networks')
  .setAction(async (taskArgs, hre) => {
    const accounts = await hre.ethers.getSigners()
    await migrate(
      await loadEnv(taskArgs, accounts[0] as unknown as Wallet),
      taskArgs,
      taskArgs.autoMine,
    )
  })
