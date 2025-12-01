import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import RewardsEligibilityOracleArtifact from '../../../artifacts/contracts/eligibility/RewardsEligibilityOracle.sol/RewardsEligibilityOracle.json'
import { deployImplementation } from './proxy/implementation'
import { deployWithTransparentUpgradeableProxy } from './proxy/TransparentUpgradeableProxy'

export default buildModule('RewardsEligibilityOracle', (m) => {
  const deployer = m.getAccount(0)
  const governor = m.getAccount(1)
  const graphTokenAddress = m.getParameter('graphTokenAddress')

  // Deploy proxy (this also deploys the implementation internally)
  const {
    proxy: RewardsEligibilityOracleProxy,
    proxyAdmin: RewardsEligibilityOracleProxyAdmin,
    implementation: RewardsEligibilityOracleImplementation,
  } = deployWithTransparentUpgradeableProxy(m, {
    name: 'RewardsEligibilityOracle',
    artifact: RewardsEligibilityOracleArtifact,
    constructorArgs: [graphTokenAddress],
    initArgs: [governor],
  })

  // Transfer ProxyAdmin ownership to governor (must be called by deployer who owns it)
  m.call(RewardsEligibilityOracleProxyAdmin, 'transferOwnership', [governor], {
    from: deployer,
    after: [RewardsEligibilityOracleProxy],
  })

  return {
    RewardsEligibilityOracle: RewardsEligibilityOracleProxy,
    RewardsEligibilityOracleProxyAdmin,
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

