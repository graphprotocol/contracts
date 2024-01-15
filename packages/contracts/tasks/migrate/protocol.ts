import { GraphChainId, deployGraphNetwork } from '@graphprotocol/sdk'
import { greTask } from '@graphprotocol/sdk/gre'

greTask('migrate', 'Deploy protocol contracts')
  .addFlag('skipConfirmation', 'Skip confirmation prompt on write actions')
  .addFlag('skipPostDeploy', 'Skip accepting ownership and unpausing protocol after deploying')
  .addFlag('force', 'Deploy contract even if its already deployed')
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
        governor: taskArgs.skipPostDeploy ? undefined : (await graph.getNamedAccounts()).governor,
        forceDeploy: taskArgs.force,
        skipConfirmation: taskArgs.skipConfirmation,
        buildAcceptTx: taskArgs.buildAcceptTx,
      },
    )
  })
