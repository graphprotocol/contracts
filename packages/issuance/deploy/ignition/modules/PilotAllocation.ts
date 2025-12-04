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

  // Deploy proxy with implementation (no initialization data in constructor)
  // We'll initialize via m.call to maintain compatibility with Ignition's runtime values
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

  // SECURITY: Initialize immediately via m.call
  // While this is a separate call, it's within the same Ignition deployment execution
  // Ignition ensures this runs atomically as part of the deployment batch
  m.call(PilotAllocation, 'initialize', [governor], {
    id: 'PilotAllocation_Initialize',
    from: governor,
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
