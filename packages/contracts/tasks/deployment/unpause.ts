import { task } from 'hardhat/config'
import { isGraphL2ChainId } from '@graphprotocol/sdk'
import { GRE_TASK_PARAMS } from '@graphprotocol/sdk/gre'

task('migrate:unpause:protocol', 'Unpause protocol (except bridge)')
  .addFlag('disableSecureAccounts', 'Disable secure accounts on GRE')
  .addOptionalParam('addressBook', GRE_TASK_PARAMS.addressBook.description)
  .addOptionalParam('graphConfig', GRE_TASK_PARAMS.graphConfig.description)
  .setAction(async (taskArgs, hre) => {
    const graph = hre.graph(taskArgs)
    const { governor } = await graph.getNamedAccounts()
    const { Controller } = graph.contracts

    console.log('> Unpausing protocol')
    const tx = await Controller.connect(governor).setPaused(false)
    await tx.wait()

    console.log('Done!')
  })

task('migrate:unpause:bridge', 'Unpause bridge')
  .addFlag('disableSecureAccounts', 'Disable secure accounts on GRE')
  .addOptionalParam('addressBook', GRE_TASK_PARAMS.addressBook.description)
  .addOptionalParam('graphConfig', GRE_TASK_PARAMS.graphConfig.description)
  .setAction(async (taskArgs, hre) => {
    const graph = hre.graph(taskArgs)
    const { governor } = await graph.getNamedAccounts()
    const { L1GraphTokenGateway, L2GraphTokenGateway } = graph.contracts

    console.log('> Unpausing bridge')
    const GraphTokenGateway = isGraphL2ChainId(graph.chainId)
      ? L2GraphTokenGateway
      : L1GraphTokenGateway
    const tx = await GraphTokenGateway.connect(governor).setPaused(false)
    await tx.wait()

    console.log('Done!')
  })
