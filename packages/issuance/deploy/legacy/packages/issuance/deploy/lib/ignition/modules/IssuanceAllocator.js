'use strict'
Object.defineProperty(exports, '__esModule', { value: true })
const modules_1 = require('@nomicfoundation/hardhat-ignition/modules')
/**
 * IssuanceAllocator Deployment Module
 *
 * Deploys the complete IssuanceAllocator system with proxy and initialization.
 *
 * This module creates:
 * 1. GraphProxyAdmin - Shared admin for all issuance proxies (owned by governance)
 * 2. IssuanceAllocator implementation - The actual contract logic
 * 3. TransparentUpgradeableProxy - Proxy pointing to implementation
 * 4. Initialized IssuanceAllocator - Proxy configured as IssuanceAllocator
 *
 * @param params - Deployment parameters
 * @returns Deployed contract instances
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const IssuanceAllocatorModule = (0, modules_1.buildModule)('IssuanceAllocator', (m) => {
  // Get typed parameters
  const owner = m.getParameter('owner')
  const graphToken = m.getParameter('graphToken')
  // Deploy shared GraphProxyAdmin2 (owned by governance from deployment)
  // This admin will manage ALL issuance-related proxy contracts
  // Separate from existing GraphProxyAdmin but same design pattern
  const proxyAdmin = m.contract('ProxyAdmin', [owner], {
    id: 'GraphProxyAdmin2',
  })
  // Deploy IssuanceAllocator implementation (needs graphToken)
  const issuanceAllocatorImpl = m.contract('IssuanceAllocator', [graphToken], {
    id: 'IssuanceAllocatorImplementation',
  })
  // Encode initialization data (initialize only needs governor)
  const initData = m.encodeFunctionCall(issuanceAllocatorImpl, 'initialize', [owner])
  // Deploy TransparentUpgradeableProxy
  const proxy = m.contract('TransparentUpgradeableProxy', [issuanceAllocatorImpl, proxyAdmin, initData], {
    id: 'IssuanceAllocatorProxy',
  })
  // Return the proxy as the main contract
  const issuanceAllocator = m.contractAt('IssuanceAllocator', proxy, {
    id: 'IssuanceAllocator',
  })
  return {
    issuanceAllocator,
    issuanceAllocatorImpl,
    proxyAdmin,
    proxy,
  }
})
exports.default = IssuanceAllocatorModule
//# sourceMappingURL=IssuanceAllocator.js.map
