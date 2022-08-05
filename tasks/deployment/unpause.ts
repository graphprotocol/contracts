import { task } from 'hardhat/config'
import { cliOpts } from '../../cli/defaults'
import { chainIdIsL2 } from '../../cli/utils'

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
    const tx = await contracts.Controller.connect(governor).setPaused(false)
    await tx.wait()

    console.log('> Unpausing bridge')
    const chainId = (await hre.ethers.provider.getNetwork()).chainId
    const isL2 = chainIdIsL2(chainId)
    const GraphTokenGateway = isL2 ? contracts.L2GraphTokenGateway : contracts.L1GraphTokenGateway
    const tx2 = await GraphTokenGateway.connect(governor).setPaused(false)
    await tx2.wait()

    console.log('Done!')
  })
