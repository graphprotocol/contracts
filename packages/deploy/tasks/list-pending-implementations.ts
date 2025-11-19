import { task } from 'hardhat/config'
import type { HardhatRuntimeEnvironment } from 'hardhat/types'
import path from 'path'

import { EnhancedIssuanceAddressBook } from '../lib/enhanced-address-book'

/**
 * List all contracts with pending implementations
 *
 * Shows which contracts have pending implementations awaiting governance approval.
 *
 * Usage:
 *   npx hardhat issuance:list-pending --network arbitrumOne
 */
task('issuance:list-pending', 'List all contracts with pending implementations').setAction(
  async (taskArgs, hre: HardhatRuntimeEnvironment) => {
    const { ethers } = hre
    const chainId = hre.network.config.chainId ?? (await ethers.provider.getNetwork()).chainId

    console.log('\n========== Pending Implementations ==========\n')
    console.log(`Network: ${hre.network.name} (chainId=${chainId})`)

    // Load address book
    const issuanceAddressBookPath = path.resolve(__dirname, '../../issuance/addresses.json')
    const addressBook = new EnhancedIssuanceAddressBook(issuanceAddressBookPath, Number(chainId))

    // Get all contracts with pending implementations
    const pendingContracts = addressBook.listPendingImplementations()

    if (pendingContracts.length === 0) {
      console.log('\n✅ No pending implementations')
      return
    }

    console.log(`\n📋 Found ${pendingContracts.length} contract(s) with pending implementations:\n`)

    for (const contractName of pendingContracts) {
      const entry = addressBook.getEntry(contractName) as any
      const pending = entry.pendingImplementation

      console.log(`📦 ${contractName}:`)
      console.log(`   Proxy: ${entry.address}`)
      console.log(`   Current implementation: ${entry.implementation || 'N/A'}`)
      console.log(`   Pending implementation: ${pending.address}`)
      if (pending.deployedAt) {
        console.log(`   Deployed at: ${pending.deployedAt}`)
      }
      if (pending.txHash) {
        console.log(`   Deploy TX: ${pending.txHash}`)
      }
      console.log(`   Ready for upgrade: ${pending.readyForUpgrade ? 'Yes' : 'No'}`)
      console.log()
    }

    console.log('🎯 Next steps:')
    console.log('   1. Generate governance TX (if not already done)')
    console.log('   2. Execute governance via Safe UI')
    console.log('   3. Sync address book after execution:')
    console.log(
      `      npx hardhat issuance:sync-pending-implementation --contract <CONTRACT_NAME> --network ${hre.network.name}`,
    )
  },
)
