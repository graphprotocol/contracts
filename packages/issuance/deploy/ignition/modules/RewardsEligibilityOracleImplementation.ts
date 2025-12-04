import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import RewardsEligibilityOracleArtifact from '../../../artifacts/contracts/eligibility/RewardsEligibilityOracle.sol/RewardsEligibilityOracle.json'
import { deployImplementation } from './proxy/implementation'

/**
 * Deploy RewardsEligibilityOracle implementation only (for upgrades)
 *
 * This module deploys a new RewardsEligibilityOracle implementation contract without
 * deploying a proxy. It's used for upgrading an existing RewardsEligibilityOracle proxy
 * to a new implementation via governance.
 *
 * Usage:
 *   npx hardhat ignition deploy ignition/modules/RewardsEligibilityOracleImplementation.ts \
 *     --parameters ignition/configs/issuance.arbitrumOne.json5 \
 *     --network arbitrumOne
 */
export default buildModule('RewardsEligibilityOracleImplementation', (m) => {
  const graphTokenAddress = m.getParameter('graphTokenAddress')

  const RewardsEligibilityOracleImplementation = deployImplementation(m, {
    name: 'RewardsEligibilityOracle',
    artifact: RewardsEligibilityOracleArtifact,
    constructorArgs: [graphTokenAddress],
  })

  return { RewardsEligibilityOracleImplementation }
})
