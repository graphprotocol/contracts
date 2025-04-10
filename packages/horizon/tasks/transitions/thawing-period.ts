import { task, types } from 'hardhat/config'
import { printBanner } from '@graphprotocol/toolshed/utils'
import { requireLocalNetwork } from '@graphprotocol/toolshed/hardhat'

task('transition:clear-thawing', 'Clears the thawing period in HorizonStaking')
  .addOptionalParam('governorIndex', 'Derivation path index for the governor account', 0, types.int)
  .addFlag('skipNetworkCheck', 'Skip the network check (use with caution)')
  .setAction(async (taskArgs, hre) => {
    printBanner('CLEARING THAWING PERIOD')

    if (!taskArgs.skipNetworkCheck) {
      requireLocalNetwork(hre)
    }

    const signers = await hre.ethers.getSigners()
    const governor = signers[taskArgs.governorIndex]
    const horizonStaking = hre.graph().horizon.contracts.HorizonStaking

    console.log('Clearing thawing period...')
    const tx = await horizonStaking.connect(governor).clearThawingPeriod()
    await tx.wait()
    console.log('Thawing period cleared')
  })
