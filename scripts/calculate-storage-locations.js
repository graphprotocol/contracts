#!/usr/bin/env node

/**
 * This script calculates the storage locations for ERC-7201 namespaced storage.
 *
 * Usage:
 * node calculate-storage-locations.js "graphprotocol.storage.ContractName"
 * node calculate-storage-locations.js --contract ContractName
 */

// Import the shared storage location utilities
const {
  getNamespace,
  getStorageStructName,
  getStorageLocationName,
  getStorageGetterName,
  getNamespacedStorageLocation,
  getERC7201FormulaComment,
  keccak256,
} = require('./utils/storage-locations')

// If run directly from command line
if (require.main === module) {
  // Check if using --contract flag
  if (process.argv[2] === '--contract') {
    const contractName = process.argv[3]

    if (!contractName) {
      console.error('Please provide a contract name.')
      console.error('Example: node calculate-storage-locations.js --contract ContractName')
      process.exit(1)
    }

    const namespace = getNamespace(contractName)
    const location = getNamespacedStorageLocation(namespace)
    const structName = getStorageStructName(contractName)
    const getterName = getStorageGetterName(contractName)
    const formulaComment = getERC7201FormulaComment(namespace)

    console.log(`Contract Name: ${contractName}`)
    console.log(`Namespace: ${namespace}`)
    console.log(`Storage Location: ${location}`)
    console.log('\nSolidity code:')
    console.log(`/// @custom:storage-location erc7201:${namespace}`)
    console.log(`struct ${structName} {`)
    console.log('    // Add your storage variables here')
    console.log('}')
    console.log(`\nfunction ${getterName}() private pure returns (${structName} storage $) {`)
    console.log(
      `    // This value was calculated using: node scripts/calculate-storage-locations.js --contract ${contractName}`,
    )
    console.log(`    ${formulaComment}`)
    console.log('    assembly {')
    console.log(`        $.slot := ${location}`)
    console.log('    }')
    console.log('}')
  } else {
    const namespace = process.argv[2]

    if (!namespace) {
      console.error('Please provide a namespace as an argument.')
      console.error('Example: node calculate-storage-locations.js "graphprotocol.storage.ContractName"')
      console.error('Or: node calculate-storage-locations.js --contract ContractName')
      process.exit(1)
    }

    const location = getNamespacedStorageLocation(namespace)
    const contractName = namespace.split('.').pop()
    const formulaComment = getERC7201FormulaComment(namespace)

    console.log(`Namespace: ${namespace}`)
    console.log(`Storage Location: ${location}`)
    console.log('\nSolidity code:')
    console.log(`function _get${contractName}Storage() private pure returns (${contractName}Data storage $) {`)
    console.log(`    // This value was calculated using: node scripts/calculate-storage-locations.js "${namespace}"`)
    console.log(`    ${formulaComment}`)
    console.log('    assembly {')
    console.log(`        $.slot := ${location}`)
    console.log('    }')
    console.log('}')
  }
}

// Re-export the shared utilities for backward compatibility
module.exports = {
  getNamespace,
  getStorageStructName,
  getStorageLocationName,
  getStorageGetterName,
  getNamespacedStorageLocation,
  getERC7201FormulaComment,
  keccak256,
}
