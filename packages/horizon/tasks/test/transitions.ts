import { task, types } from 'hardhat/config'
import { ethers } from 'ethers'

import { printBanner } from 'hardhat-graph-protocol/sdk'

task('transition:unset-subgraph-service', 'Unsets the subgraph service in HorizonStaking')
  .addOptionalParam('governorIndex', 'Derivation path index for the governor account', 0, types.int)
  .addFlag('skipNetworkCheck', 'Skip the network check (use with caution)')
  .setAction(async (taskArgs, hre) => {
    printBanner('UNSETTING SUBGRAPH SERVICE')

    // Check that we're on a local network
    if (!taskArgs.skipNetworkCheck && hre.network.name !== 'localhost' && hre.network.name !== 'hardhat') {
      throw new Error('This task can only be run on localhost or hardhat network. Use --skip-network-check to override (use with caution)')
    }

    const signers = await hre.ethers.getSigners()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const governor = signers[taskArgs.governorIndex] as any
    const rewardsManager = hre.graph().horizon!.contracts.RewardsManager

    console.log('Unsetting subgraph service...')
    const tx = await rewardsManager.connect(governor).setSubgraphService(ethers.ZeroAddress)
    await tx.wait()
    console.log('Subgraph service unset')
  })

task('transition:clear-thawing', 'Clears the thawing period in HorizonStaking')
  .addOptionalParam('governorIndex', 'Derivation path index for the governor account', 0, types.int)
  .addFlag('skipNetworkCheck', 'Skip the network check (use with caution)')
  .setAction(async (taskArgs, hre) => {
    printBanner('CLEARING THAWING PERIOD')

    // Check that we're on a local network
    if (!taskArgs.skipNetworkCheck && hre.network.name !== 'localhost' && hre.network.name !== 'hardhat') {
      throw new Error('This task can only be run on localhost or hardhat network. Use --skip-network-check to override (use with caution)')
    }

    const signers = await hre.ethers.getSigners()
    const governor = signers[taskArgs.governorIndex]
    const horizonStaking = hre.graph().horizon!.contracts.HorizonStaking

    console.log('Clearing thawing period...')
    const tx = await horizonStaking.connect(governor).clearThawingPeriod()
    await tx.wait()
    console.log('Thawing period cleared')
  })

task('transition:enable-delegation-slashing', 'Enables delegation slashing in HorizonStaking')
  .addOptionalParam('governorIndex', 'Derivation path index for the governor account', 0, types.int)
  .addFlag('skipNetworkCheck', 'Skip the network check (use with caution)')
  .setAction(async (taskArgs, hre) => {
    printBanner('ENABLING DELEGATION SLASHING')

    // Check that we're on a local network
    if (!taskArgs.skipNetworkCheck && hre.network.name !== 'localhost' && hre.network.name !== 'hardhat') {
      throw new Error('This task can only be run on localhost or hardhat network. Use --skip-network-check to override (use with caution)')
    }

    const signers = await hre.ethers.getSigners()
    const governor = signers[taskArgs.governorIndex]
    const horizonStaking = hre.graph().horizon!.contracts.HorizonStaking

    console.log('Enabling delegation slashing...')
    const tx = await horizonStaking.connect(governor).setDelegationSlashingEnabled()
    await tx.wait()

    // Log if the delegation slashing is enabled
    const delegationSlashingEnabled = await horizonStaking.isDelegationSlashingEnabled()
    console.log('Delegation slashing enabled:', delegationSlashingEnabled)
  })
