/**
 * IssuanceAllocator Address Book Utilities
 *
 * This script demonstrates how to use the common address book utilities
 * to retrieve IssuanceAllocator contract addresses from Ignition deployments.
 */

const { getContractAddress, getAllContractAddresses } = require('@graphprotocol/common')

/**
 * Get IssuanceAllocator contract address for a network
 * @param {string|number} networkNameOrChainId - Network name or chain ID
 * @returns {string} Contract address
 */
function getIssuanceAllocatorAddress(networkNameOrChainId) {
  return getContractAddress('issuance', networkNameOrChainId, 'IssuanceAllocator')
}

/**
 * Get ProxyAdmin address for IssuanceAllocator
 * @param {string|number} networkNameOrChainId - Network name or chain ID
 * @returns {string} ProxyAdmin address
 */
function getIssuanceProxyAdminAddress(networkNameOrChainId) {
  return getContractAddress('issuance', networkNameOrChainId, 'IssuanceAllocatorProxyAdmin')
}

/**
 * Get all IssuanceAllocator deployment addresses
 * @param {string|number} networkNameOrChainId - Network name or chain ID
 * @returns {Object} All contract addresses
 */
function getAllIssuanceAddresses(networkNameOrChainId) {
  return getAllContractAddresses('issuance', networkNameOrChainId)
}

/**
 * Print deployment summary for a network
 * @param {string|number} networkNameOrChainId - Network name or chain ID
 */
function printDeploymentSummary(networkNameOrChainId) {
  try {
    console.log(`\n📋 IssuanceAllocator Deployment Summary for ${networkNameOrChainId}`)
    console.log('='.repeat(60))

    const addresses = getAllIssuanceAddresses(networkNameOrChainId)

    for (const [contractName, address] of Object.entries(addresses)) {
      console.log(`${contractName.padEnd(30)} ${address}`)
    }

    console.log('='.repeat(60))
  } catch (error) {
    console.error(`❌ No deployment found for ${networkNameOrChainId}: ${error.message}`)
  }
}

// Export utilities
module.exports = {
  getIssuanceAllocatorAddress,
  getIssuanceProxyAdminAddress,
  getAllIssuanceAddresses,
  printDeploymentSummary,
}

// CLI usage
if (require.main === module) {
  const network = process.argv[2] || 'hardhat'
  printDeploymentSummary(network)
}
