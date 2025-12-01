import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import RewardsEligibilityOracleArtifact from '../../../../../issuance/artifacts/contracts/eligibility/RewardsEligibilityOracle.sol/RewardsEligibilityOracle.json'

/**
 * Reference module for deployed RewardsEligibilityOracle
 *
 * This module doesn't deploy anything - it just creates a reference to the
 * already-deployed REO contract from the issuance package.
 */
export default buildModule('RewardsEligibilityOracleRef', (m) => {
  const address = m.getParameter('rewardsEligibilityOracleAddress')

  const rewardsEligibilityOracle = m.contractAt(
    'RewardsEligibilityOracle',
    RewardsEligibilityOracleArtifact,
    address,
    {
      id: 'RewardsEligibilityOracle',
    },
  )

  return { rewardsEligibilityOracle }
})
