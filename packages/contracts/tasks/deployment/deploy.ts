import { task } from 'hardhat/config'

import {
  GraphChainId,
  deployGraphNetwork,
  helpers,
  isGraphChainL1Localhost,
} from '@graphprotocol/sdk'
import { GRE_TASK_PARAMS } from '@graphprotocol/sdk/gre'

task('migrate', 'Migrate contracts')
  .addParam(
    'addressBook',
    GRE_TASK_PARAMS.addressBook.description,
    GRE_TASK_PARAMS.addressBook.default,
  )
  .addParam(
    'graphConfig',
    GRE_TASK_PARAMS.graphConfig.description,
    GRE_TASK_PARAMS.graphConfig.default,
  )
  .addFlag('disableSecureAccounts', 'Disable secure accounts on GRE')
  .addFlag('skipConfirmation', GRE_TASK_PARAMS.skipConfirmation.description)
  .addFlag('force', GRE_TASK_PARAMS.force.description)
  .addFlag('buildAcceptTx', '...')
  .setAction(async (taskArgs, hre) => {
    const graph = hre.graph(taskArgs)

    await deployGraphNetwork(
      taskArgs.addressBook,
      taskArgs.graphConfig,
      graph.chainId as GraphChainId, // TODO: fix type
      await graph.getDeployer(),
      graph.provider,
      {
        forceDeploy: taskArgs.force,
        skipConfirmation: taskArgs.skipConfirmation,
        buildAcceptTx: taskArgs.buildAcceptTx,
      },
    )
  })
