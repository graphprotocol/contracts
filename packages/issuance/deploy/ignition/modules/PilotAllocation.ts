import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import TransparentUpgradeableProxyArtifact from '@openzeppelin/contracts/build/contracts/TransparentUpgradeableProxy.json'

import DirectAllocationArtifact from '../../../artifacts/contracts/allocate/DirectAllocation.sol/DirectAllocation.json'
import GraphIssuanceProxyAdminModule from './GraphIssuanceProxyAdmin'
import { deployImplementation } from './proxy/implementation'
import { loadProxyWithABI } from './proxy/utils'

/**
 * PilotAllocation - Declarative module for deployment and upgrades
 *
 * This module uses Ignition's declarative model for deployment:
 *
 * FIRST RUN:
 *   npx hardhat ignition deploy ignition/modules/PilotAllocation.ts --network arbitrumOne
 *   Deploys: GraphIssuanceProxyAdmin → Implementation → TransparentUpgradeableProxy (with atomic init)
 *   Initialization: ATOMIC via proxy constructor (prevents front-running attacks)
 *
 * SUBSEQUENT RUNS:
 *   Same command - Ignition detects existing deployments automatically
 *   Deploys: ONLY new implementation (if code changed)
 *   Upgrade: Via governance transaction ProxyAdmin.upgradeAndCall(proxy, newImpl, '0x')
 *
 * Security: Proxy is initialized ATOMICALLY in the same transaction as deployment via
 * m.encodeFunctionCall(), completely eliminating front-running attack vectors where an
 * attacker could call initialize() before governance. The initialization data is passed
 * directly to the TransparentUpgradeableProxy constructor.
 *
 * Note: PilotAllocation uses DirectAllocation as its implementation contract.
 *
 * Uses standard OpenZeppelin TransparentUpgradeableProxy + ProxyAdmin (NOT Graph protocol's
 * custom GraphProxy). This ensures complete independence from @graphprotocol/contracts.
 */
export default buildModule('PilotAllocation', (m) => {
  const governor = m.getAccount(1)
  const graphTokenAddress = m.getParameter('graphTokenAddress')
  const { GraphIssuanceProxyAdmin } = m.useModule(GraphIssuanceProxyAdminModule)

  // Always deploy latest implementation
  const PilotAllocationImplementation = deployImplementation(m, {
    name: 'PilotAllocation',
    artifact: DirectAllocationArtifact,
    constructorArgs: [graphTokenAddress],
  })

  // SECURITY: Encode initialization data using m.encodeFunctionCall
  // This works with Ignition's Future values (governor from m.getAccount)
  const initData = m.encodeFunctionCall(PilotAllocationImplementation, 'initialize', [governor])

  // Deploy proxy with implementation AND initialization data
  // This achieves truly atomic initialization - the proxy is initialized in the same
  // transaction as deployment, completely preventing any front-running attacks
  const TransparentUpgradeableProxy = m.contract(
    'TransparentUpgradeableProxy',
    TransparentUpgradeableProxyArtifact,
    [PilotAllocationImplementation, GraphIssuanceProxyAdmin, initData],
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
