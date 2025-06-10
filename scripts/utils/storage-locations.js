/**
 * Shared utilities for calculating ERC-7201 namespaced storage locations.
 * This module provides the corrected algorithm that should be used by both
 * calculate-storage-locations.js and verify-storage-slots.js scripts.
 */

const { keccak_256 } = require('@noble/hashes/sha3')

/**
 * Generate a standard namespace for a contract
 * @param {string} contractName - The name of the contract
 * @returns {string} The namespace string
 */
function getNamespace(contractName) {
  return `graphprotocol.storage.${contractName}`
}

/**
 * Generate a standard storage struct name
 * @param {string} contractName - The name of the contract
 * @returns {string} The struct name
 */
function getStorageStructName(contractName) {
  return `${contractName}Data`
}

/**
 * Generate a standard storage location variable name
 * @param {string} contractName - The name of the contract
 * @returns {string} The variable name
 */
function getStorageLocationName(contractName) {
  return `${contractName}StorageLocation`
}

/**
 * Generate a standard storage getter function name
 * @param {string} contractName - The name of the contract
 * @returns {string} The function name
 */
function getStorageGetterName(contractName) {
  return `_get${contractName}Storage`
}

/**
 * Generate the ERC-7201 formula comment for a given namespace
 * @param {string} namespace - The namespace string
 * @returns {string} The formula comment
 */
function getERC7201FormulaComment(namespace) {
  return `// keccak256(abi.encode(uint256(keccak256("${namespace}")) - 1)) & ~bytes32(uint256(0xff))`
}

/**
 * Calculate the storage slot for a namespace using ERC-7201 standard
 * @param {string} namespace - The namespace string
 * @returns {string} The storage slot
 */
function getNamespacedStorageLocation(namespace) {
  // Calculate keccak256 hash of the namespace
  const namespaceHash = keccak256(namespace)

  // Convert to BigInt, subtract 1
  const bn = BigInt(`0x${namespaceHash}`) - 1n

  // Convert back to hex
  let hex = bn.toString(16)
  if (hex.length % 2 !== 0) {
    hex = '0' + hex
  }
  hex = '0x' + hex

  // Clear the last byte
  const mask = BigInt('0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00')
  const cleared = (BigInt(hex) & mask).toString(16)

  return '0x' + cleared
}

/**
 * Ethereum keccak256 implementation using @noble/hashes
 * This is the CORRECT implementation that matches Ethereum's keccak256,
 * which is different from NIST SHA-3.
 * @param {string} input - The input string
 * @returns {string} The hash as a hex string
 */
function keccak256(input) {
  const inputBytes = new TextEncoder().encode(input)
  const hashBytes = keccak_256(inputBytes)
  return Array.from(hashBytes, (byte) => byte.toString(16).padStart(2, '0')).join('')
}

module.exports = {
  getNamespace,
  getStorageStructName,
  getStorageLocationName,
  getStorageGetterName,
  getNamespacedStorageLocation,
  getERC7201FormulaComment,
  keccak256,
}
