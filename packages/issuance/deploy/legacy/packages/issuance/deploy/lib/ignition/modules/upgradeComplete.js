'use strict'
Object.defineProperty(exports, '__esModule', { value: true })
const modules_1 = require('@nomicfoundation/hardhat-ignition/modules')
/**
 * IssuanceAllocator Complete Upgrade Module
 *
 * Complete upgrade process for testing - combines both phases:
 * 1. Deploy new implementation (Phase 1 - Permissionless)
 * 2. Execute upgrade via ProxyAdmin (Phase 2 - Governance)
 *
 * This module is for testing environments only where the deployer
 * has governance permissions. In production, use separate prep and
 * governance modules for proper governance workflow.
 *
 * ⚠️  WARNING: This module requires governance permissions!
 *
 * Use cases:
 * - Local development and testing
 * - Integration test environments
 * - Scenarios where deployer has ProxyAdmin ownership
 *
 * For production deployments, use:
 * 1. upgradePrep.ts (permissionless)
 * 2. governanceUpgrade.ts (governance-only)
 * 3. verifyUpgradeState.ts (verification)
 *
 * @param params - Complete upgrade parameters
 * @returns New implementation and upgrade result
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const UpgradeCompleteModule = (0, modules_1.buildModule)('IssuanceAllocatorUpgradeComplete', (m) => {
  // Get required parameters
  const graphToken = m.getParameter('graphToken')
  const issuanceAllocatorProxyAddress = m.getParameter('issuanceAllocatorProxyAddress')
  const proxyAdminAddress = m.getParameter('proxyAdminAddress')
  // Phase 1: Deploy new implementation (permissionless)
  const newImplementation = m.contract('IssuanceAllocator', [graphToken], {
    id: 'NewIssuanceAllocatorImplementation',
  })
  // Phase 2: Execute upgrade (governance required)
  const proxyAdmin = m.contractAt('ProxyAdmin', proxyAdminAddress, {
    id: 'CompleteUpgradeProxyAdmin',
  })
  m.call(proxyAdmin, 'upgrade', [issuanceAllocatorProxyAddress, newImplementation], {
    id: 'ExecuteCompleteUpgrade',
  })
  return {
    newImplementation,
    proxyAdmin,
  }
})
exports.default = UpgradeCompleteModule
//# sourceMappingURL=upgradeComplete.js.map
