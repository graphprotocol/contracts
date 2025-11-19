#!/usr/bin/env node

/**
 * Deploy Governance Upgrade Script
 *
 * This script:
 * 1. Executes the governance upgrade on-chain
 * 2. Syncs the address book with the completed upgrade
 * 3. Shows updated deployment status
 *
 * Usage:
 *   node scripts/deploy-governance-upgrade.js <network>
 *   node scripts/deploy-governance-upgrade.js hardhat
 *   node scripts/deploy-governance-upgrade.js sepolia
 */

const { execSync } = require('child_process')
const { activatePendingImplementation, printDeploymentStatus } = require('./update-address-book')

/**
 * Execute governance upgrade and update address book
 *
 * @param {string} network - Network name
 */
async function deployGovernanceUpgrade(network) {
  console.log(`🏛️  Starting governance upgrade on ${network}`)
  console.log('='.repeat(60))

  try {
    // Step 1: Check if there's a pending implementation
    console.log(`\n🔍 Step 1: Checking for pending implementation...`)
    printDeploymentStatus(network)

    // Step 2: Execute governance upgrade
    console.log(`\n⚡ Step 2: Executing governance upgrade...`)

    const upgradeCommand =
      network === 'hardhat' ? `pnpm upgrade:governance:local` : `pnpm upgrade:governance:${network}`

    console.log(`Running: ${upgradeCommand}`)
    const upgradeOutput = execSync(upgradeCommand, {
      encoding: 'utf8',
      cwd: process.cwd(),
    })

    console.log(upgradeOutput)

    // Step 3: Sync address book with completed upgrade
    console.log(`\n📋 Step 3: Syncing address book with completed upgrade...`)

    activatePendingImplementation(network, 'IssuanceAllocator')

    // Step 4: Show updated deployment status
    console.log(`\n📊 Step 4: Updated deployment status:`)
    printDeploymentStatus(network)

    console.log(`\n✅ Governance upgrade completed successfully!`)
    console.log(`\n🎯 Next steps:`)
    console.log(`   1. Verify upgrade state: pnpm verify:upgrade:${network}`)
    console.log(`   2. Test the upgraded contract functionality`)
  } catch (error) {
    console.error(`\n❌ Governance upgrade failed:`)
    console.error(error.message)
    console.error(`\n🔧 Troubleshooting:`)
    console.error(`   1. Check if there's a pending implementation`)
    console.error(`   2. Verify governance permissions`)
    console.error(`   3. Check network connectivity`)
    process.exit(1)
  }
}

/**
 * Main execution
 */
async function main() {
  const network = process.argv[2]

  if (!network) {
    console.error('Usage: node scripts/deploy-governance-upgrade.js <network>')
    console.error('Example: node scripts/deploy-governance-upgrade.js hardhat')
    process.exit(1)
  }

  // Validate network
  const supportedNetworks = ['hardhat', 'local', 'sepolia', 'mainnet', 'arbitrumOne', 'arbitrumSepolia']
  if (!supportedNetworks.includes(network)) {
    console.error(`Unsupported network: ${network}`)
    console.error(`Supported networks: ${supportedNetworks.join(', ')}`)
    process.exit(1)
  }

  await deployGovernanceUpgrade(network)
}

// Run if called directly
if (require.main === module) {
  main().catch(console.error)
}

module.exports = {
  deployGovernanceUpgrade,
}
