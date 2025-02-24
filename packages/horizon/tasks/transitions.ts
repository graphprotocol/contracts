import { task, types } from 'hardhat/config'

task('transition:clear-thawing', 'Clears the thawing period in HorizonStaking')
  .addOptionalParam('governorIndex', 'Index of the governor account in getSigners array', 0, types.int)
  .setAction(async (taskArgs, hre) => {
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
