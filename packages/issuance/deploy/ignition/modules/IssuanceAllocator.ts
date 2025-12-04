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

  // SECURITY: Encode initialization data using m.encodeFunctionCall
  // This works with Ignition's Future values (governor from m.getAccount)
  const initData = m.encodeFunctionCall(IssuanceAllocatorImplementation, 'initialize', [governor])

  // Deploy proxy with implementation AND initialization data
  // This achieves truly atomic initialization - the proxy is initialized in the same
  // transaction as deployment, completely preventing any front-running attacks
  const TransparentUpgradeableProxy = m.contract(
    'TransparentUpgradeableProxy',
    TransparentUpgradeableProxyArtifact,
    [IssuanceAllocatorImplementation, GraphIssuanceProxyAdmin, initData],
    { id: 'IssuanceAllocator_Proxy' },
  )

  // Load proxy with IssuanceAllocator ABI for typed access
  const IssuanceAllocator = loadProxyWithABI(m, TransparentUpgradeableProxy, {
    name: 'IssuanceAllocator',
    artifact: IssuanceAllocatorArtifact,
  })

  return {
    IssuanceAllocator,
    IssuanceAllocatorImplementation,
  }
})
