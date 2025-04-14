import { task, types } from 'hardhat/config'
import { printBanner } from '@graphprotocol/toolshed/utils'
import { requireLocalNetwork } from '@graphprotocol/toolshed/hardhat'

task('transition:enable-delegation-slashing', 'Enables delegation slashing in HorizonStaking')
  .addOptionalParam('governorIndex', 'Derivation path index for the governor account', 1, types.int)
  .addFlag('skipNetworkCheck', 'Skip the network check (use with caution)')
  .setAction(async (taskArgs, hre) => {
    printBanner('ENABLING DELEGATION SLASHING')

    if (!taskArgs.skipNetworkCheck) {
      requireLocalNetwork(hre)
    }

    const graph = hre.graph()
    const governor = await graph.accounts.getGovernor(taskArgs.governorIndex)
    const horizonStaking = graph.horizon.contracts.HorizonStaking

    console.log('Enabling delegation slashing...')
    await horizonStaking.connect(governor).setDelegationSlashingEnabled()

    // Log if the delegation slashing is enabled
    const delegationSlashingEnabled = await horizonStaking.isDelegationSlashingEnabled()
    console.log('Delegation slashing enabled:', delegationSlashingEnabled)
  })
