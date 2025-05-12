#!/usr/bin/env node

/**
 * This script calculates the storage locations for ERC-7201 namespaced storage.
 *
 * Usage:
 * node calculate-storage-locations.js "graphprotocol.storage.ContractName"
 * node calculate-storage-locations.js --contract ContractName
 */

const crypto = require('crypto');

/**
 * Generate a standard namespace for a contract
 * @param {string} contractName - The name of the contract
 * @returns {string} The namespace string
 */
function getNamespace(contractName) {
  return `graphprotocol.storage.${contractName}`;
}

/**
 * Generate a standard storage struct name
 * @param {string} contractName - The name of the contract
 * @returns {string} The struct name
 */
function getStorageStructName(contractName) {
  return `${contractName}Data`;
}

/**
 * Generate a standard storage location variable name
 * @param {string} contractName - The name of the contract
 * @returns {string} The variable name
 */
function getStorageLocationName(contractName) {
  return `${contractName}StorageLocation`;
}

/**
 * Generate a standard storage getter function name
 * @param {string} contractName - The name of the contract
 * @returns {string} The function name
 */
function getStorageGetterName(contractName) {
  return `_get${contractName}Storage`;
}

/**
 * Calculate the storage slot for a namespace
 * @param {string} namespace - The namespace string
 * @returns {string} The storage slot
 */
function getNamespacedStorageLocation(namespace) {
  // Calculate keccak256 hash of the namespace
  const namespaceHash = keccak256(namespace);

  // Convert to BigInt, subtract 1
  const bn = BigInt(`0x${namespaceHash}`) - 1n;

  // Convert back to hex
  let hex = bn.toString(16);
  if (hex.length % 2 !== 0) {
    hex = '0' + hex;
  }
  hex = '0x' + hex;

  // Clear the last byte
  const mask = BigInt('0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00');
  const cleared = (BigInt(hex) & mask).toString(16);

  return '0x' + cleared;
}

/**
 * Simple keccak256 implementation using Node.js crypto
 * @param {string} input - The input string
 * @returns {string} The hash as a hex string
 */
function keccak256(input) {
  const hash = crypto.createHash('sha3-256');
  hash.update(Buffer.from(input, 'utf8'));
  return hash.digest('hex');
}

// If run directly from command line
if (require.main === module) {
  // Check if using --contract flag
  if (process.argv[2] === '--contract') {
    const contractName = process.argv[3];

    if (!contractName) {
      console.error('Please provide a contract name.');
      console.error('Example: node calculate-storage-locations.js --contract ContractName');
      process.exit(1);
    }

    const namespace = getNamespace(contractName);
    const location = getNamespacedStorageLocation(namespace);
    const structName = getStorageStructName(contractName);
    const getterName = getStorageGetterName(contractName);

    console.log(`Contract Name: ${contractName}`);
    console.log(`Namespace: ${namespace}`);
    console.log(`Storage Location: ${location}`);
    console.log(`\nSolidity code:`);
    console.log(`/// @custom:storage-location erc7201:${namespace}`);
    console.log(`struct ${structName} {`);
    console.log(`    // Add your storage variables here`);
    console.log(`}`);
    console.log(`\nfunction ${getterName}() private pure returns (${structName} storage $) {`);
    console.log(`    // This value was calculated using: node scripts/calculate-storage-locations.js --contract ${contractName}`);
    console.log(`    assembly {`);
    console.log(`        $.slot := ${location}`);
    console.log(`    }`);
    console.log(`}`);
  } else {
    const namespace = process.argv[2];

    if (!namespace) {
      console.error('Please provide a namespace as an argument.');
      console.error('Example: node calculate-storage-locations.js "graphprotocol.storage.ContractName"');
      console.error('Or: node calculate-storage-locations.js --contract ContractName');
      process.exit(1);
    }

    const location = getNamespacedStorageLocation(namespace);
    const contractName = namespace.split('.').pop();

    console.log(`Namespace: ${namespace}`);
    console.log(`Storage Location: ${location}`);
    console.log(`\nSolidity code:`);
    console.log(`function _get${contractName}Storage() private pure returns (${contractName}Data storage $) {`);
    console.log(`    // This value was calculated using: node scripts/calculate-storage-locations.js "${namespace}"`);
    console.log(`    assembly {`);
    console.log(`        $.slot := ${location}`);
    console.log(`    }`);
    console.log(`}`);
  }
}

module.exports = {
  getNamespace,
  getStorageStructName,
  getStorageLocationName,
  getStorageGetterName,
  getNamespacedStorageLocation,
  keccak256
};
