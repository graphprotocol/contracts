import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import TransparentUpgradeableProxyArtifact from '@openzeppelin/contracts/build/contracts/TransparentUpgradeableProxy.json'

import IssuanceAllocatorArtifact from '../../../artifacts/contracts/allocate/IssuanceAllocator.sol/IssuanceAllocator.json'
import GraphIssuanceProxyAdminModule from './GraphIssuanceProxyAdmin'
import { deployImplementation } from './proxy/implementation'
import { loadProxyWithABI } from './proxy/utils'

/**
 * IssuanceAllocator - Declarative module for deployment and upgrades
 *
 * This module handles both initial deployment and upgrades using a unified pattern:
 *
 * INITIAL DEPLOYMENT (no issuanceAllocatorAddress parameter):
 *   npx hardhat ignition deploy ignition/modules/IssuanceAllocator.ts --network arbitrumOne
 *   Deploys: GraphIssuanceProxyAdmin → Implementation → TransparentUpgradeableProxy
 *   Orchestration: upgradeAndCall(proxy, implementation, initializeData) to initialize
 *
 * UPGRADE (provide issuanceAllocatorAddress parameter):
 *   npx hardhat ignition deploy ignition/modules/IssuanceAllocator.ts \
 *     --parameters '{"issuanceAllocatorAddress":"0x..."}' --network arbitrumOne
 *   Deploys: ONLY new implementation, references existing proxy
 *   Orchestration: upgradeAndCall(proxy, newImplementation, '0x') to upgrade
 *
 * Key insight: Both flows use upgradeAndCall transaction pattern. The module parameter
 * explicitly indicates whether to deploy a new proxy or reference an existing one.
 *
 * Uses standard OpenZeppelin TransparentUpgradeableProxy + ProxyAdmin (NOT Graph protocol's
 * custom GraphProxy). This ensures complete independence from @graphprotocol/contracts.
 */
export default buildModule('IssuanceAllocator', (m) => {
  const graphTokenAddress = m.getParameter('graphTokenAddress')
  const { GraphIssuanceProxyAdmin } = m.useModule(GraphIssuanceProxyAdminModule)

  // Always deploy latest implementation
  const IssuanceAllocatorImplementation = deployImplementation(m, {
    name: 'IssuanceAllocator',
    artifact: IssuanceAllocatorArtifact,
    constructorArgs: [graphTokenAddress],
  })

  // Deploy proxy with implementation (no init data - initialization via upgrade transaction)
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

  return {
    IssuanceAllocator,
    IssuanceAllocatorImplementation,
  }
})

// Legacy migrate module for backward compatibility
export const MigrateIssuanceAllocatorModule = buildModule('IssuanceAllocatorMigrate', (m) => {
  const issuanceAllocatorAddress = m.getParameter('issuanceAllocatorAddress')

  const IssuanceAllocator = m.contractAt('IssuanceAllocator', IssuanceAllocatorArtifact, issuanceAllocatorAddress)

  return { IssuanceAllocator }
})
