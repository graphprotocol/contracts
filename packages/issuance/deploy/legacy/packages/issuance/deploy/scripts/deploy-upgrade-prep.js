#!/usr/bin/env node

/**
 * Deploy Upgrade Preparation Script
 *
 * This script:
 * 1. Deploys a new IssuanceAllocator implementation
 * 2. Updates the address book with pending implementation
 * 3. Shows deployment status
 *
 * Usage:
 *   node scripts/deploy-upgrade-prep.js <network>
 *   node scripts/deploy-upgrade-prep.js hardhat
 *   node scripts/deploy-upgrade-prep.js sepolia
 */

const { execSync } = require('child_process')
const { updateAddressBookPendingImplementation, printDeploymentStatus } = require('./update-address-book')

/**
 * Deploy new implementation and update address book
 *
 * @param {string} network - Network name
 */
async function deployUpgradePrep(network) {
  console.log(`🚀 Starting upgrade preparation deployment on ${network}`)
  console.log('='.repeat(60))

  try {
    // Step 1: Deploy new implementation using Ignition
    console.log(`\n📦 Step 1: Deploying new IssuanceAllocator implementation...`)

    const deployCommand = network === 'hardhat' ? `pnpm deploy:impl:local` : `pnpm deploy:impl:${network}`

    console.log(`Running: ${deployCommand}`)
    const deployOutput = execSync(deployCommand, {
      encoding: 'utf8',
      cwd: process.cwd(),
    })

    console.log(deployOutput)

    // Step 2: Parse deployment result
    console.log(`\n📋 Step 2: Updating address book with pending implementation...`)

    // Extract deployed address from output
    const addressMatch = deployOutput.match(
      /IssuanceAllocatorUpgradePrep#NewIssuanceAllocatorImplementation - (0x[a-fA-F0-9]{40})/,
    )
    if (!addressMatch) {
      throw new Error('Could not extract deployed implementation address from output')
    }

    const implementationAddress = addressMatch[1]
    console.log(`New implementation deployed at: ${implementationAddress}`)

    // Step 3: Update address book (simulate deployment result structure)
    const mockDeploymentResult = {
      deployedAddresses: {
        'IssuanceAllocatorUpgradePrep#NewIssuanceAllocatorImplementation': implementationAddress,
      },
    }

    updateAddressBookPendingImplementation(
      network,
      'IssuanceAllocator',
      mockDeploymentResult,
      'IssuanceAllocatorUpgradePrep#NewIssuanceAllocatorImplementation',
    )

    // Step 4: Show deployment status
    console.log(`\n📊 Step 3: Current deployment status:`)
    printDeploymentStatus(network)

    console.log(`\n✅ Upgrade preparation completed successfully!`)
    console.log(`\n🎯 Next steps:`)
    console.log(`   1. Review the pending implementation`)
    console.log(`   2. Run governance upgrade: pnpm upgrade:governance:${network}`)
    console.log(`   3. Verify upgrade state: pnpm verify:upgrade:${network}`)
  } catch (error) {
    console.error(`\n❌ Upgrade preparation failed:`)
    console.error(error.message)
    process.exit(1)
  }
}

/**
 * Main execution
 */
async function main() {
  const network = process.argv[2]

  if (!network) {
    console.error('Usage: node scripts/deploy-upgrade-prep.js <network>')
    console.error('Example: node scripts/deploy-upgrade-prep.js hardhat')
    process.exit(1)
  }

  // Validate network
  const supportedNetworks = ['hardhat', 'local', 'sepolia', 'mainnet', 'arbitrumOne', 'arbitrumSepolia']
  if (!supportedNetworks.includes(network)) {
    console.error(`Unsupported network: ${network}`)
    console.error(`Supported networks: ${supportedNetworks.join(', ')}`)
    process.exit(1)
  }

  await deployUpgradePrep(network)
}

// Run if called directly
if (require.main === module) {
  main().catch(console.error)
}

module.exports = {
  deployUpgradePrep,
}
