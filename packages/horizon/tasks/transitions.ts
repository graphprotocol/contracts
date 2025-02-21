import { task } from 'hardhat/config'

task('transition:clear-thawing', 'Clears the thawing period in HorizonStaking')
  .setAction(async (_, hre) => {
    const [governor] = await hre.ethers.getSigners()
    const horizonStaking = hre.graph().horizon!.contracts.HorizonStaking

    console.log('Clearing thawing period...')
    const tx = await horizonStaking.connect(governor).clearThawingPeriod()
    await tx.wait()
    console.log('Thawing period cleared')
  })

task('transition:enable-delegation-slashing', 'Enables delegation slashing in HorizonStaking')
  .setAction(async (_, hre) => {
    const [governor] = await hre.ethers.getSigners()
    const horizonStaking = hre.graph().horizon!.contracts.HorizonStaking

    console.log('Enabling delegation slashing...')
    const tx = await horizonStaking.connect(governor).setDelegationSlashingEnabled()
    await tx.wait()
    console.log('Delegation slashing enabled')
  })
