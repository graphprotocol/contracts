import {
  GraphChainId,
  GraphNetworkGovernedContractNameList,
  acceptOwnership,
  deployGraphNetwork,
  setPausedProtocol,
} from '@graphprotocol/sdk'
import { graphTask } from '@graphprotocol/sdk/gre'
import { ContractTransaction } from 'ethers'

graphTask('migrate', 'Deploy protocol contracts')
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

    if (!taskArgs.skipPostDeploy) {
      // Governor accepts ownership of contracts
      const governor = (await graph.getNamedAccounts()).governor
      const txs: ContractTransaction[] = []
      for (const contract of GraphNetworkGovernedContractNameList) {
        const tx = await acceptOwnership(graph.contracts, governor, { contractName: contract })
        if (tx) {
          txs.push()
        }
      }
      await Promise.all(txs.map((tx) => tx.wait()))

      // Governor unpauses the protocol
      await setPausedProtocol(graph.contracts, governor, { paused: false })
    }
  })
