import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import RewardsEligibilityOracleArtifact from '../../../artifacts/contracts/eligibility/RewardsEligibilityOracle.sol/RewardsEligibilityOracle.json'
import GraphProxyAdmin2Module from './GraphProxyAdmin2'
import { deployWithGraphProxy } from './proxy/GraphProxy'

export default buildModule('RewardsEligibilityOracle', (m) => {
  const governor = m.getAccount(1)
  const graphTokenAddress = m.getParameter('graphTokenAddress')

  // Use shared GraphProxyAdmin2
  const { GraphProxyAdmin2 } = m.useModule(GraphProxyAdmin2Module)

  // Deploy proxy using GraphProxy pattern with shared admin
  const { proxy: RewardsEligibilityOracleProxy, implementation: RewardsEligibilityOracleImplementation } =
    deployWithGraphProxy(m, GraphProxyAdmin2, {
      name: 'RewardsEligibilityOracle',
      artifact: RewardsEligibilityOracleArtifact,
      constructorArgs: [graphTokenAddress],
      initArgs: [governor],
    })

  return {
    RewardsEligibilityOracle: RewardsEligibilityOracleProxy,
    RewardsEligibilityOracleImplementation,
  }
})

// Module for connecting to existing RewardsEligibilityOracle deployment
export const MigrateRewardsEligibilityOracleModule = buildModule('RewardsEligibilityOracleMigrate', (m) => {
  const rewardsEligibilityOracleAddress = m.getParameter('rewardsEligibilityOracleAddress')

  const RewardsEligibilityOracle = m.contractAt(
    'RewardsEligibilityOracle',
    RewardsEligibilityOracleArtifact,
    rewardsEligibilityOracleAddress,
  )

  return { RewardsEligibilityOracle }
})
