'use strict'
Object.defineProperty(exports, '__esModule', { value: true })
const modules_1 = require('@nomicfoundation/hardhat-ignition/modules')
/**
 * IssuanceAllocator Upgrade Preparation Module
 *
 * Phase 1 of upgrade process - Permissionless:
 * 1. Deploy new IssuanceAllocator implementation
 * 2. Verify the implementation is valid
 *
 * This can be executed by anyone and prepares for governance upgrade.
 * The new implementation is deployed but not yet activated.
 *
 * After this phase, governance can execute the upgrade using the
 * governanceUpgrade module with the new implementation address.
 *
 * @param params - Upgrade preparation parameters
 * @returns New implementation contract and address
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const UpgradePrepModule = (0, modules_1.buildModule)('IssuanceAllocatorUpgradePrep', (m) => {
  // Get required parameters from global scope
  const graphToken = m.getParameter('graphToken')
  // Deploy new IssuanceAllocator implementation
  const newImplementation = m.contract('IssuanceAllocator', [graphToken], {
    id: 'NewIssuanceAllocatorImplementation',
  })
  return {
    newImplementation,
  }
})
exports.default = UpgradePrepModule
//# sourceMappingURL=upgradePrep.js.map
