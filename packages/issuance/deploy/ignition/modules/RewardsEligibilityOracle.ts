import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import TransparentUpgradeableProxyArtifact from '@openzeppelin/contracts/build/contracts/TransparentUpgradeableProxy.json'

import RewardsEligibilityOracleArtifact from '../../../artifacts/contracts/eligibility/RewardsEligibilityOracle.sol/RewardsEligibilityOracle.json'
import GraphIssuanceProxyAdminModule from './GraphIssuanceProxyAdmin'
import { deployImplementation } from './proxy/implementation'
import { loadProxyWithABI } from './proxy/utils'

/**
 * RewardsEligibilityOracle - Declarative module for deployment and upgrades
 *
 * This module uses Ignition's declarative model to handle both initial deployment and upgrades:
 *
 * FIRST RUN:
 *   npx hardhat ignition deploy ignition/modules/RewardsEligibilityOracle.ts --network arbitrumOne
 *   Deploys: GraphIssuanceProxyAdmin → Implementation → TransparentUpgradeableProxy
 *   Orchestration: upgradeAndCall(proxy, implementation, initializeData) to initialize
 *
 * SUBSEQUENT RUNS:
 *   Same command - Ignition detects existing deployments automatically
 *   Deploys: ONLY new implementation (if code changed)
 *   Orchestration: upgradeAndCall(proxy, newImplementation, '0x') to upgrade
 *
 * Key insight: Ignition's state management handles deduplication. The module always declares
 * the desired end state, and Ignition ensures already-deployed contracts aren't redeployed.
 *
 * Uses standard OpenZeppelin TransparentUpgradeableProxy + ProxyAdmin (NOT Graph protocol's
 * custom GraphProxy). This ensures complete independence from @graphprotocol/contracts.
 */
export default buildModule('RewardsEligibilityOracle', (m) => {
  const graphTokenAddress = m.getParameter('graphTokenAddress')
  const { GraphIssuanceProxyAdmin } = m.useModule(GraphIssuanceProxyAdminModule)

  // Always deploy latest implementation
  const RewardsEligibilityOracleImplementation = deployImplementation(m, {
    name: 'RewardsEligibilityOracle',
    artifact: RewardsEligibilityOracleArtifact,
    constructorArgs: [graphTokenAddress],
  })

  // Deploy proxy with implementation (no init data - initialization via upgrade transaction)
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
