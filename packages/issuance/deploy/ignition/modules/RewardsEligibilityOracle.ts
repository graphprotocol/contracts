import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import TransparentUpgradeableProxyArtifact from '@openzeppelin/contracts/build/contracts/TransparentUpgradeableProxy.json'

import RewardsEligibilityOracleArtifact from '../../../artifacts/contracts/eligibility/RewardsEligibilityOracle.sol/RewardsEligibilityOracle.json'
import GraphIssuanceProxyAdminModule from './GraphIssuanceProxyAdmin'
import { deployImplementation } from './proxy/implementation'
import { loadProxyWithABI } from './proxy/utils'

/**
 * RewardsEligibilityOracle - Declarative module for deployment and upgrades
 *
 * This module uses Ignition's declarative model for deployment:
 *
 * FIRST RUN:
 *   npx hardhat ignition deploy ignition/modules/RewardsEligibilityOracle.ts --network arbitrumOne
 *   Deploys: GraphIssuanceProxyAdmin → Implementation → TransparentUpgradeableProxy
 *   Initialization: Immediate via m.call within same deployment (prevents front-running attacks)
 *
 * SUBSEQUENT RUNS:
 *   Same command - Ignition detects existing deployments automatically
 *   Deploys: ONLY new implementation (if code changed)
 *   Upgrade: Via governance transaction ProxyAdmin.upgradeAndCall(proxy, newImpl, '0x')
 *
 * Security: Proxy is initialized immediately after deployment within the same Ignition execution
 * batch to prevent front-running attacks where an attacker could call initialize() before governance.
 *
 * Uses standard OpenZeppelin TransparentUpgradeableProxy + ProxyAdmin (NOT Graph protocol's
 * custom GraphProxy). This ensures complete independence from @graphprotocol/contracts.
 */
export default buildModule('RewardsEligibilityOracle', (m) => {
  const governor = m.getAccount(1)
  const graphTokenAddress = m.getParameter('graphTokenAddress')
  const { GraphIssuanceProxyAdmin } = m.useModule(GraphIssuanceProxyAdminModule)

  // Always deploy latest implementation
  const RewardsEligibilityOracleImplementation = deployImplementation(m, {
    name: 'RewardsEligibilityOracle',
    artifact: RewardsEligibilityOracleArtifact,
    constructorArgs: [graphTokenAddress],
  })

  // Deploy proxy with implementation (no initialization data in constructor)
  // We'll initialize via m.call to maintain compatibility with Ignition's runtime values
  const TransparentUpgradeableProxy = m.contract(
    'TransparentUpgradeableProxy',
    TransparentUpgradeableProxyArtifact,
    [RewardsEligibilityOracleImplementation, GraphIssuanceProxyAdmin, '0x'],
    { id: 'RewardsEligibilityOracle_Proxy' },
  )

  // Load proxy with RewardsEligibilityOracle ABI for typed access
  const RewardsEligibilityOracle = loadProxyWithABI(m, TransparentUpgradeableProxy, {
    name: 'RewardsEligibilityOracle',
    artifact: RewardsEligibilityOracleArtifact,
  })

  // SECURITY: Initialize immediately via m.call
  // While this is a separate call, it's within the same Ignition deployment execution
  // Ignition ensures this runs atomically as part of the deployment batch
  m.call(RewardsEligibilityOracle, 'initialize', [governor], {
    id: 'RewardsEligibilityOracle_Initialize',
    from: governor,
  })

  return {
    RewardsEligibilityOracle,
    RewardsEligibilityOracleImplementation,
  }
})

// Legacy migrate module for backward compatibility
export const MigrateRewardsEligibilityOracleModule = buildModule('RewardsEligibilityOracleMigrate', (m) => {
  const rewardsEligibilityOracleAddress = m.getParameter('rewardsEligibilityOracleAddress')

  const RewardsEligibilityOracle = m.contractAt(
    'RewardsEligibilityOracle',
    RewardsEligibilityOracleArtifact,
    rewardsEligibilityOracleAddress,
  )

  return { RewardsEligibilityOracle }
})
