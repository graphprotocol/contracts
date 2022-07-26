import { task } from 'hardhat/config'
import { cliOpts } from '../../cli/defaults'

task('migrate:unpause', 'Unpause protocol')
  .addParam('addressBook', cliOpts.addressBook.description, cliOpts.addressBook.default)
  .addParam('graphConfig', cliOpts.graphConfig.description, cliOpts.graphConfig.default)
  .setAction(async (taskArgs, hre) => {
    const { contracts, getNamedAccounts } = hre.graph({
      addressBook: taskArgs.addressBook,
      graphConfig: taskArgs.graphConfig,
    })
    const { governor } = await getNamedAccounts()

    console.log('> Unpausing protocol')
    const tx = await contracts.Controller.connect(governor.signer).setPaused(false)
    await tx.wait()
    console.log('Done!')
  })
