/**
 * Sync Ignition deployment addresses to main addresses.json
 *
 * This script reads deployed addresses from Hardhat Ignition's deployment artifacts
 * and updates the main addresses.json file with the correct format.
 *
 * Usage:
 *   npx ts-node scripts/sync-addresses.ts <deployment-id> <chain-id>
 *
 * Example:
 *   npx ts-node scripts/sync-addresses.ts issuance-arbitrumSepolia 421614
 */

import fs from 'fs'
import path from 'path'

interface IgnitionDeployedAddresses {
  [key: string]: string
}

interface AddressBookEntry {
  address: string
  proxy?: string
  proxyAdmin?: string
  implementation?: string
}

interface AddressBook {
  [chainId: string]: {
    [contractName: string]: AddressBookEntry
  }
}

function syncAddresses(deploymentId: string, chainId: string) {
  const deploymentPath = path.join(__dirname, '..', 'ignition', 'deployments', deploymentId)
  const deployedAddressesPath = path.join(deploymentPath, 'deployed_addresses.json')
  const addressBookPath = path.join(__dirname, '..', 'addresses.json')

  // Check if deployment exists
  if (!fs.existsSync(deployedAddressesPath)) {
    console.error(`Deployment not found: ${deployedAddressesPath}`)
    process.exit(1)
  }

  // Load deployed addresses from Ignition
  const deployedAddresses: IgnitionDeployedAddresses = JSON.parse(fs.readFileSync(deployedAddressesPath, 'utf8'))

  // Load existing address book
  const addressBook: AddressBook = JSON.parse(fs.readFileSync(addressBookPath, 'utf8'))

  // Ensure chain ID exists in address book
  if (!addressBook[chainId]) {
    addressBook[chainId] = {}
  }

  // Extract contract addresses from Ignition deployment
  const contracts = ['IssuanceAllocator', 'DirectAllocation', 'RewardsEligibilityOracle']

  for (const contractName of contracts) {
    // Find proxy address (the main contract address)
    const proxyKey = Object.keys(deployedAddresses).find(
      (key) =>
        key.includes(`${contractName}_ProxyWithABI`) || key.includes(`TransparentUpgradeableProxy_${contractName}`),
    )

    // Find implementation address
    const implKey = Object.keys(deployedAddresses).find(
      (key) => key.includes(`${contractName}#${contractName}`) && !key.includes('ProxyAdmin'),
    )

    // Find proxy admin address
    const proxyAdminKey = Object.keys(deployedAddresses).find((key) => key.includes(`ProxyAdmin_${contractName}`))

    if (proxyKey) {
      const entry: AddressBookEntry = {
        address: deployedAddresses[proxyKey],
        proxy: 'transparent',
      }

      if (implKey) {
        entry.implementation = deployedAddresses[implKey]
      }

      if (proxyAdminKey) {
        entry.proxyAdmin = deployedAddresses[proxyAdminKey]
      }

      addressBook[chainId][contractName] = entry
      console.log(`✓ Updated ${contractName}:`)
      console.log(`  Address: ${entry.address}`)
      if (entry.implementation) console.log(`  Implementation: ${entry.implementation}`)
      if (entry.proxyAdmin) console.log(`  ProxyAdmin: ${entry.proxyAdmin}`)
    } else {
      console.warn(`⚠ Could not find deployment for ${contractName}`)
    }
  }

  // Write updated address book
  fs.writeFileSync(addressBookPath, JSON.stringify(addressBook, null, 2) + '\n')
  console.log(`\n✓ Address book updated: ${addressBookPath}`)
}

// Main execution
const args = process.argv.slice(2)
if (args.length < 2) {
  console.error('Usage: npx ts-node scripts/sync-addresses.ts <deployment-id> <chain-id>')
  console.error('Example: npx ts-node scripts/sync-addresses.ts issuance-arbitrumSepolia 421614')
  process.exit(1)
}

const [deploymentId, chainId] = args
syncAddresses(deploymentId, chainId)
