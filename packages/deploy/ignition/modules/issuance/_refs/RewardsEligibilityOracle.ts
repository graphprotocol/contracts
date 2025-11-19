import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

/**
 * Reference module for deployed RewardsEligibilityOracle
 *
 * This module doesn't deploy anything - it just creates a reference to the
 * already-deployed REO contract from the issuance package.
 */
export default buildModule('RewardsEligibilityOracleRef', (m) => {
  const address = m.getParameter('rewardsEligibilityOracleAddress')

  const rewardsEligibilityOracle = m.contractAt('RewardsEligibilityOracle', address, {
    id: 'RewardsEligibilityOracle',
  })

  return { rewardsEligibilityOracle }
})
