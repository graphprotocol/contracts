import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import RewardsEligibilityOracleArtifact from '../../../artifacts/contracts/eligibility/RewardsEligibilityOracle.sol/RewardsEligibilityOracle.json'
import { deployImplementation } from './proxy/implementation'
import { deployWithTransparentUpgradeableProxy } from './proxy/TransparentUpgradeableProxy'

export default buildModule('RewardsEligibilityOracle', (m) => {
  const governor = m.getAccount(1)
  const graphTokenAddress = m.getParameter('graphTokenAddress')

  // Deploy RewardsEligibilityOracle implementation
  const RewardsEligibilityOracleImplementation = deployImplementation(m, {
    name: 'RewardsEligibilityOracle',
    artifact: RewardsEligibilityOracleArtifact,
    constructorArgs: [graphTokenAddress],
  })

  // Deploy proxy
  const { proxy: RewardsEligibilityOracleProxy, proxyAdmin: RewardsEligibilityOracleProxyAdmin } =
    deployWithTransparentUpgradeableProxy(m, {
      name: 'RewardsEligibilityOracle',
      artifact: RewardsEligibilityOracleArtifact,
      constructorArgs: [graphTokenAddress],
      initArgs: [governor],
    })

  // Transfer ProxyAdmin ownership to governor
  m.call(RewardsEligibilityOracleProxyAdmin, 'transferOwnership', [governor], {
    after: [RewardsEligibilityOracleProxy],
  })

  return {
    RewardsEligibilityOracle: RewardsEligibilityOracleProxy,
    RewardsEligibilityOracleImplementation,
    RewardsEligibilityOracleProxyAdmin,
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

