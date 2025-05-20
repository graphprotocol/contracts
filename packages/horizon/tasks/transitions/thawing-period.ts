import { task, types } from 'hardhat/config'
import { printBanner } from '@graphprotocol/toolshed/utils'
import { requireLocalNetwork } from '@graphprotocol/toolshed/hardhat'

task('transition:clear-thawing', 'Clears the thawing period in HorizonStaking')
  .addOptionalParam('governorIndex', 'Derivation path index for the governor account', 1, types.int)
  .addFlag('skipNetworkCheck', 'Skip the network check (use with caution)')
  .setAction(async (taskArgs, hre) => {
    printBanner('CLEARING THAWING PERIOD')

    if (!taskArgs.skipNetworkCheck) {
      requireLocalNetwork(hre)
    }

    const graph = hre.graph()
    const governor = await graph.accounts.getGovernor(taskArgs.governorIndex)
    const horizonStaking = graph.horizon.contracts.HorizonStaking

    console.log('Clearing thawing period...')
    await horizonStaking.connect(governor).clearThawingPeriod()
    console.log('Thawing period cleared')
  })
