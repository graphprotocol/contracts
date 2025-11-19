import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

/**
 * Reference module for existing RewardsManager deployment
 *
 * This module doesn't deploy anything - it just creates a reference to the
 * already-deployed RewardsManager contract from the Horizon package.
 */
export default buildModule('RewardsManagerRef', (m) => {
  const address = m.getParameter('rewardsManagerAddress')

  const rewardsManager = m.contractAt('IRewardsManager', address, {
    id: 'RewardsManager',
  })

  return { rewardsManager }
})
