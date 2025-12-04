import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import TransparentUpgradeableProxyArtifact from '@openzeppelin/contracts/build/contracts/TransparentUpgradeableProxy.json'

import DirectAllocationArtifact from '../../../artifacts/contracts/allocate/DirectAllocation.sol/DirectAllocation.json'
import GraphIssuanceProxyAdminModule from './GraphIssuanceProxyAdmin'
import { deployImplementation } from './proxy/implementation'
import { loadProxyWithABI } from './proxy/utils'

/**
 * PilotAllocation - Declarative module for deployment and upgrades
 *
 * This module uses Ignition's declarative model to handle both initial deployment and upgrades:
 *
 * FIRST RUN:
 *   npx hardhat ignition deploy ignition/modules/PilotAllocation.ts --network arbitrumOne
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
 * Note: PilotAllocation uses DirectAllocation as its implementation contract.
 *
 * Uses standard OpenZeppelin TransparentUpgradeableProxy + ProxyAdmin (NOT Graph protocol's
 * custom GraphProxy). This ensures complete independence from @graphprotocol/contracts.
 */
export default buildModule('PilotAllocation', (m) => {
  const graphTokenAddress = m.getParameter('graphTokenAddress')
  const { GraphIssuanceProxyAdmin } = m.useModule(GraphIssuanceProxyAdminModule)

  // Always deploy latest implementation
  const PilotAllocationImplementation = deployImplementation(m, {
    name: 'PilotAllocation',
    artifact: DirectAllocationArtifact,
    constructorArgs: [graphTokenAddress],
  })

  // Deploy proxy with implementation (no init data - initialization via upgrade transaction)
  const TransparentUpgradeableProxy = m.contract(
    'TransparentUpgradeableProxy',
    TransparentUpgradeableProxyArtifact,
    [PilotAllocationImplementation, GraphIssuanceProxyAdmin, '0x'],
    { id: 'PilotAllocation_Proxy' },
  )

  // Load proxy with DirectAllocation ABI for typed access
  const PilotAllocation = loadProxyWithABI(m, TransparentUpgradeableProxy, {
    name: 'PilotAllocation',
    artifact: DirectAllocationArtifact,
  })

  return {
    PilotAllocation,
    PilotAllocationImplementation,
  }
})

// Legacy migrate module for backward compatibility
export const MigratePilotAllocationModule = buildModule('PilotAllocationMigrate', (m) => {
  const pilotAllocationAddress = m.getParameter('pilotAllocationAddress')

  const PilotAllocation = m.contractAt('DirectAllocation', DirectAllocationArtifact, pilotAllocationAddress)

  return { PilotAllocation }
})
