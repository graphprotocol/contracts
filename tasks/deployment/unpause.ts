import { task } from 'hardhat/config'
import { cliOpts } from '../../cli/defaults'

task('migrate:unpause', 'Unpause protocol')
  .addOptionalParam('addressBook', cliOpts.addressBook.description)
  .addOptionalParam('graphConfig', cliOpts.graphConfig.description)
  .setAction(async (taskArgs, hre) => {
    const { contracts, getNamedAccounts } = hre.graph(taskArgs)
    const { governor } = await getNamedAccounts()

    console.log('> Unpausing protocol')
    const tx = await contracts.Controller.connect(governor).setPaused(false)
    await tx.wait()
    console.log('Done!')
  })
