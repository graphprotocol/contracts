/**
 * Address Book Update Utilities for Issuance Deployment
 *
 * This script provides utilities to update the address book with deployment
 * information, including support for pending implementations during upgrades.
 */

const fs = require('fs')
const path = require('path')

/**
 * Update address book with initial deployment information
 *
 * @param {string} network - Network name
 * @param {Object} deploymentResult - Ignition deployment result
 */
function updateAddressBookInitialDeployment(network, deploymentResult) {
  console.log(`📋 Updating address book for initial deployment on ${network}`)

  const addressBookPath = getAddressBookPath(network)
  const addressBook = loadAddressBook(addressBookPath)

  // Extract deployment information from Ignition result
  const deployedAddresses = deploymentResult.deployedAddresses || {}

  // Update IssuanceAllocator (proxy)
  if (deployedAddresses['IssuanceAllocator#IssuanceAllocator']) {
    addressBook.IssuanceAllocator = {
      address: deployedAddresses['IssuanceAllocator#IssuanceAllocator'],
      proxy: true,
      implementation: {
        address: deployedAddresses['IssuanceAllocator#IssuanceAllocatorImplementation'],
        constructorArgs: [], // Will be filled from deployment metadata
        txHash: '', // Will be filled from deployment metadata
      },
      initArgs: [], // Will be filled from deployment metadata
      txHash: '', // Will be filled from deployment metadata
    }
  }

  // Update GraphProxyAdmin2
  if (deployedAddresses['IssuanceAllocator#GraphProxyAdmin2']) {
    addressBook.GraphProxyAdmin2 = {
      address: deployedAddresses['IssuanceAllocator#GraphProxyAdmin2'],
      constructorArgs: [], // Will be filled from deployment metadata
      txHash: '', // Will be filled from deployment metadata
    }
  }

  // Save updated address book
  saveAddressBook(addressBookPath, addressBook)
  console.log(`✅ Address book updated for initial deployment`)
}

/**
 * Update address book with pending implementation from Ignition deployment
 *
 * @param {string} network - Network name
 * @param {string} contractName - Name of the proxy contract
 * @param {Object} deploymentResult - Ignition deployment result
 * @param {string} implementationModuleName - Name of the implementation module in deployment
 */
function updateAddressBookPendingImplementation(network, contractName, deploymentResult, implementationModuleName) {
  console.log(`📋 Setting pending implementation for ${contractName} on ${network}`)

  const addressBookPath = getAddressBookPath(network)
  const addressBook = loadAddressBook(addressBookPath)

  if (!addressBook[contractName]) {
    throw new Error(`Contract ${contractName} not found in address book`)
  }

  if (!addressBook[contractName].proxy) {
    throw new Error(`Contract ${contractName} is not a proxy contract`)
  }

  // Extract implementation address from deployment result
  const deployedAddresses = deploymentResult.deployedAddresses || {}
  const implementationAddress = deployedAddresses[implementationModuleName]

  if (!implementationAddress) {
    throw new Error(`Implementation address not found for module: ${implementationModuleName}`)
  }

  // Add pending implementation
  addressBook[contractName].pendingImplementation = {
    address: implementationAddress,
    deployedAt: new Date().toISOString(),
    readyForUpgrade: true,
    // TODO: Add deployment metadata (txHash, constructorArgs, etc.)
  }

  // Save updated address book
  saveAddressBook(addressBookPath, addressBook)
  console.log(`✅ Pending implementation set: ${implementationAddress}`)
}

/**
 * Activate pending implementation (move from pending to active)
 *
 * @param {string} network - Network name
 * @param {string} contractName - Name of the proxy contract
 */
function activatePendingImplementation(network, contractName) {
  console.log(`📋 Activating pending implementation for ${contractName} on ${network}`)

  const addressBookPath = getAddressBookPath(network)
  const addressBook = loadAddressBook(addressBookPath)

  if (!addressBook[contractName]) {
    throw new Error(`Contract ${contractName} not found in address book`)
  }

  if (!addressBook[contractName].pendingImplementation) {
    throw new Error(`No pending implementation found for ${contractName}`)
  }

  // Move pending to active
  const pendingImpl = addressBook[contractName].pendingImplementation
  addressBook[contractName].implementation = {
    address: pendingImpl.address,
    constructorArgs: pendingImpl.constructorArgs,
    creationCodeHash: pendingImpl.creationCodeHash,
    runtimeCodeHash: pendingImpl.runtimeCodeHash,
    txHash: pendingImpl.txHash,
  }

  // Remove pending implementation
  delete addressBook[contractName].pendingImplementation

  // Save updated address book
  saveAddressBook(addressBookPath, addressBook)
  console.log(`✅ Address book synced: ${addressBook[contractName].implementation.address}`)
}

/**
 * Get address book file path for network
 *
 * @param {string} network - Network name
 * @returns {string} Path to address book file
 */
function getAddressBookPath(network) {
  return path.join(__dirname, '..', `addresses-${network}.json`)
}

/**
 * Load address book from file
 *
 * @param {string} filePath - Path to address book file
 * @returns {Object} Address book object
 */
function loadAddressBook(filePath) {
  try {
    if (fs.existsSync(filePath)) {
      const content = fs.readFileSync(filePath, 'utf8')
      return JSON.parse(content)
    }
    return {}
  } catch (error) {
    console.warn(`Warning: Could not load address book from ${filePath}: ${error.message}`)
    return {}
  }
}

/**
 * Save address book to file
 *
 * @param {string} filePath - Path to address book file
 * @param {Object} addressBook - Address book object
 */
function saveAddressBook(filePath, addressBook) {
  try {
    // Ensure directory exists
    const dir = path.dirname(filePath)
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true })
    }

    // Write formatted JSON
    fs.writeFileSync(filePath, JSON.stringify(addressBook, null, 2))
  } catch (error) {
    throw new Error(`Failed to save address book to ${filePath}: ${error.message}`)
  }
}

/**
 * Print deployment status for a network
 *
 * @param {string} network - Network name
 */
function printDeploymentStatus(network) {
  console.log(`\n📋 Deployment Status for ${network}`)
  console.log('='.repeat(60))

  const addressBookPath = getAddressBookPath(network)
  const addressBook = loadAddressBook(addressBookPath)

  for (const [contractName, entry] of Object.entries(addressBook)) {
    console.log(`\n${contractName}:`)
    console.log(`  Address: ${entry.address}`)

    if (entry.proxy) {
      console.log(`  Proxy: Yes`)
      if (entry.implementation) {
        console.log(`  Implementation: ${entry.implementation.address}`)
      }
      if (entry.pendingImplementation) {
        console.log(`  🟡 Pending Implementation: ${entry.pendingImplementation.address}`)
        console.log(`     Ready for Upgrade: ${entry.pendingImplementation.readyForUpgrade}`)
        console.log(`     Deployed At: ${entry.pendingImplementation.deployedAt}`)
      }
    }
  }

  console.log('\n' + '='.repeat(60))
}

// Export utilities
module.exports = {
  updateAddressBookInitialDeployment,
  updateAddressBookPendingImplementation,
  activatePendingImplementation,
  printDeploymentStatus,
}

// CLI usage
if (require.main === module) {
  const command = process.argv[2]
  const network = process.argv[3] || 'hardhat'

  switch (command) {
    case 'status':
      printDeploymentStatus(network)
      break
    case 'activate': {
      const contractName = process.argv[4]
      if (!contractName) {
        console.error('Usage: node update-address-book.js activate <network> <contractName>')
        process.exit(1)
      }
      activatePendingImplementation(network, contractName)
      break
    }
    default:
      console.log('Usage:')
      console.log('  node update-address-book.js status [network]')
      console.log('  node update-address-book.js activate <network> <contractName>')
  }
}
