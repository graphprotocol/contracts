'use strict'
Object.defineProperty(exports, '__esModule', { value: true })
const modules_1 = require('@nomicfoundation/hardhat-ignition/modules')
/**
 * IssuanceAllocator Governance Transaction Generator
 *
 * This module generates governance transactions without executing them.
 * Useful for creating transactions that need to be signed by governance multi-sig.
 *
 * The transactions can be:
 * 1. Generated and logged for manual execution
 * 2. Signed locally for testing
 * 3. Submitted to governance multi-sig for production
 * 4. Used with governance frameworks (Governor, Gnosis Safe, etc.)
 *
 * Output includes:
 * - Complete transaction details (to, data, description)
 * - Encoded calldata for direct use
 * - Contract references for verification
 *
 * This enables flexible governance workflows while maintaining
 * deployment tracking and verification capabilities.
 *
 * @param params - Transaction generation parameters
 * @returns Transaction data and contract references
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const GovernanceTransactionsModule = (0, modules_1.buildModule)('IssuanceAllocatorGovernanceTransactions', (m) => {
  // Parameters for the upgrade transaction
  const proxyAdminAddress = m.getParameter('proxyAdminAddress')
  const proxyAddress = m.getParameter('proxyAddress')
  const newImplementationAddress = m.getParameter('newImplementationAddress')
  // Get contracts for transaction generation using external artifacts
  const proxyAdmin = m.contractAt('ProxyAdmin', proxyAdminAddress, {
    id: 'GovernanceProxyAdmin',
  })
  const proxy = m.contractAt('TransparentUpgradeableProxy', proxyAddress, {
    id: 'GovernanceProxy',
  })
  const newImplementation = m.contractAt('IssuanceAllocator', newImplementationAddress, {
    id: 'GovernanceNewImplementation',
  })
  return {
    proxyAdmin,
    proxy,
    newImplementation,
  }
})
exports.default = GovernanceTransactionsModule
//# sourceMappingURL=governanceTransactions.js.map
