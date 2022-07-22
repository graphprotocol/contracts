import { task } from 'hardhat/config'
import { cliOpts } from '../../cli/defaults'

task('migrate:unpause', 'Unpause protocol')
  .addParam('addressBook', cliOpts.addressBook.description, cliOpts.addressBook.default)
  .setAction(async (taskArgs, hre) => {
    const { contracts } = hre.graph({ addressBook: taskArgs.addressBook })
    const [, , governor] = await hre.ethers.getSigners()

    console.log('> Unpausing protocol')
    const tx = await contracts.Controller.connect(governor).setPaused(false)
    await tx.wait()
    console.log('Done!')
  })
