import { task, types } from 'hardhat/config'
import { ethers } from 'ethers'

task('transition:unset-subgraph-service', 'Unsets the subgraph service in HorizonStaking')
  .addOptionalParam('governorIndex', 'Index of the governor account in getSigners array', 0, types.int)
  .setAction(async (taskArgs, hre) => {
    console.log(getTransitionBanner('UNSETTING SUBGRAPH SERVICE'))

    const signers = await hre.ethers.getSigners()
    const governor = signers[taskArgs.governorIndex]
    const rewardsManager = hre.graph().horizon!.contracts.RewardsManager

    console.log('Unsetting subgraph service...')
    const tx = await rewardsManager.connect(governor).setSubgraphService(ethers.ZeroAddress)
    await tx.wait()
    console.log('Subgraph service unset')
  })

task('transition:clear-thawing', 'Clears the thawing period in HorizonStaking')
  .addOptionalParam('governorIndex', 'Index of the governor account in getSigners array', 0, types.int)
  .setAction(async (taskArgs, hre) => {
    console.log(getTransitionBanner('CLEARING THAWING PERIOD'))

    const signers = await hre.ethers.getSigners()
    const governor = signers[taskArgs.governorIndex]
    const horizonStaking = hre.graph().horizon!.contracts.HorizonStaking

    console.log('Clearing thawing period...')
    const tx = await horizonStaking.connect(governor).clearThawingPeriod()
    await tx.wait()
    console.log('Thawing period cleared')
  })

task('transition:enable-delegation-slashing', 'Enables delegation slashing in HorizonStaking')
  .addOptionalParam('governorIndex', 'Index of the governor account in getSigners array', 0, types.int)
  .setAction(async (taskArgs, hre) => {
    console.log(getTransitionBanner('ENABLING DELEGATION SLASHING'))

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

function getTransitionBanner(title: string): string {
  const bannerWidth = 47 // Total width inside the box
  const fullText = title

  // Calculate padding needed to center the text
  const totalPadding = bannerWidth - fullText.length
  const leftPadding = Math.floor(totalPadding / 2)
  const rightPadding = totalPadding - leftPadding

  const centeredText = ' '.repeat(leftPadding) + fullText + ' '.repeat(rightPadding)

  return `
+-----------------------------------------------+
|                                               |
|${centeredText}|
|                                               |
+-----------------------------------------------+
`
}
