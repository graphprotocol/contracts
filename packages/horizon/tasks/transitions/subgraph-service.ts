import { task, types } from 'hardhat/config'
import { ethers } from 'ethers'
import { printBanner } from '@graphprotocol/toolshed/utils'
import { requireLocalNetwork } from '@graphprotocol/toolshed/hardhat'

task('transition:unset-subgraph-service', 'Unsets the subgraph service in HorizonStaking')
  .addOptionalParam('governorIndex', 'Derivation path index for the governor account', 1, types.int)
  .addFlag('skipNetworkCheck', 'Skip the network check (use with caution)')
  .setAction(async (taskArgs, hre) => {
    printBanner('UNSETTING SUBGRAPH SERVICE')

    if (!taskArgs.skipNetworkCheck) {
      requireLocalNetwork(hre)
    }

    const graph = hre.graph()
    const governor = await graph.accounts.getGovernor(taskArgs.governorIndex)
    const rewardsManager = graph.horizon.contracts.RewardsManager

    console.log('Unsetting subgraph service...')
    await rewardsManager.connect(governor).setSubgraphService(ethers.ZeroAddress)
    console.log('Subgraph service unset')
  })
