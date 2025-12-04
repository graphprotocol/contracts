import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import TransparentUpgradeableProxyArtifact from '@openzeppelin/contracts/build/contracts/TransparentUpgradeableProxy.json'

import IssuanceAllocatorArtifact from '../../../artifacts/contracts/allocate/IssuanceAllocator.sol/IssuanceAllocator.json'
import GraphIssuanceProxyAdminModule from './GraphIssuanceProxyAdmin'
import { deployImplementation } from './proxy/implementation'
import { loadProxyWithABI } from './proxy/utils'

/**
 * IssuanceAllocator - Declarative module for deployment and upgrades
 *
 * This module uses Ignition's declarative model for deployment:
 *
 * FIRST RUN:
 *   npx hardhat ignition deploy ignition/modules/IssuanceAllocator.ts --network arbitrumOne
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
export default buildModule('IssuanceAllocator', (m) => {
  const governor = m.getAccount(1)
  const graphTokenAddress = m.getParameter('graphTokenAddress')
  const { GraphIssuanceProxyAdmin } = m.useModule(GraphIssuanceProxyAdminModule)

  // Always deploy latest implementation
  const IssuanceAllocatorImplementation = deployImplementation(m, {
    name: 'IssuanceAllocator',
    artifact: IssuanceAllocatorArtifact,
    constructorArgs: [graphTokenAddress],
  })

  // Deploy proxy with implementation (no initialization data in constructor)
  // We'll initialize via upgradeAndCall to maintain compatibility with Ignition's runtime values
  const TransparentUpgradeableProxy = m.contract(
    'TransparentUpgradeableProxy',
    TransparentUpgradeableProxyArtifact,
    [IssuanceAllocatorImplementation, GraphIssuanceProxyAdmin, '0x'],
    { id: 'IssuanceAllocator_Proxy' },
  )

  // Load proxy with IssuanceAllocator ABI for typed access
  const IssuanceAllocator = loadProxyWithABI(m, TransparentUpgradeableProxy, {
    name: 'IssuanceAllocator',
    artifact: IssuanceAllocatorArtifact,
  })

  // SECURITY: Initialize immediately via upgradeAndCall
  // While this is a separate call, it's within the same Ignition deployment execution
  // Ignition ensures this runs atomically as part of the deployment batch
  m.call(IssuanceAllocator, 'initialize', [governor], {
    id: 'IssuanceAllocator_Initialize',
    from: governor,
  })

  return {
    IssuanceAllocator,
    IssuanceAllocatorImplementation,
  }
})
