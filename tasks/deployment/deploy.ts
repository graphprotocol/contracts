import { Wallet } from 'ethers'
import { graphTask } from '../../gre/gre'

import { loadEnv } from '../../cli/env'
import { cliOpts } from '../../cli/defaults'
import { migrate } from '../../cli/commands/migrate'

graphTask('migrate', 'Migrate contracts')
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
