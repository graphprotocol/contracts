'use strict'
Object.defineProperty(exports, '__esModule', { value: true })
const modules_1 = require('@nomicfoundation/hardhat-ignition/modules')
/**
 * IssuanceAllocator Governance Upgrade Module
 *
 * Phase 2 of upgrade process - Governance:
 * 1. Reference the pre-deployed implementation (from Phase 1)
 * 2. Execute the proxy upgrade via ProxyAdmin
 *
 * This should only be executed by governance after thorough review
 * of the new implementation deployed in Phase 1.
 *
 * Prerequisites:
 * - New implementation must be deployed (use upgradePrep module)
 * - Caller must have ProxyAdmin ownership (governance)
 * - Implementation must be compatible with existing proxy
 *
 * @param params - Governance upgrade parameters
 * @returns Upgrade execution result and addresses
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const GovernanceUpgradeModule = (0, modules_1.buildModule)('IssuanceAllocatorGovernanceUpgrade', (m) => {
  // Get required parameters from global scope (no defaults - must be provided)
  const issuanceAllocatorProxyAddress = m.getParameter('issuanceAllocatorProxyAddress')
  const proxyAdminAddress = m.getParameter('proxyAdminAddress')
  const newImplementationAddress = m.getParameter('newImplementationAddress')
  // Step 1: Reference the existing GraphProxyAdmin2 using dependency-compiled artifact
  const proxyAdmin = m.contractAt('ProxyAdmin', proxyAdminAddress, {
    id: 'GovernanceGraphProxyAdmin2',
  })
  // Step 2: Reference the proxy contract
  const proxy = m.contractAt('TransparentUpgradeableProxy', issuanceAllocatorProxyAddress, {
    id: 'GovernanceProxy',
  })
  // Step 3: Reference the new implementation contract
  const newImplementation = m.contractAt('IssuanceAllocator', newImplementationAddress, {
    id: 'GovernanceNewImplementation',
  })
  // Step 4: Execute the upgrade
  // This calls ProxyAdmin.upgradeAndCall(proxy, newImplementation, data)
  // Using empty data since we don't need to call any function after upgrade
  m.call(proxyAdmin, 'upgradeAndCall', [proxy, newImplementationAddress, '0x'], {
    id: 'ExecuteIssuanceAllocatorUpgrade',
  })
  return {
    proxyAdmin,
    proxy,
    newImplementation,
  }
})
exports.default = GovernanceUpgradeModule
//# sourceMappingURL=governanceUpgrade.js.map
