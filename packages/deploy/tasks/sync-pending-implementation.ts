import { task } from 'hardhat/config'
import type { HardhatRuntimeEnvironment } from 'hardhat/types'
import path from 'path'

import { EnhancedIssuanceAddressBook } from '../lib/enhanced-address-book'

/**
 * Sync pending implementation to active after governance execution
 *
 * This task:
 * 1. Verifies that the on-chain implementation matches the pending implementation
 * 2. Updates the address book to mark the pending implementation as active
 * 3. Clears the pending implementation field
 *
 * Call this AFTER governance has executed the upgrade on-chain.
 *
 * Usage:
 *   npx hardhat issuance:sync-pending-implementation --contract RewardsManager --network arbitrumOne
 */
task(
  'issuance:sync-pending-implementation',
  'Mark pending implementation as active after governance execution',
)
  .addParam('contract', 'Contract name (e.g., RewardsManager, IssuanceAllocator)')
  .addOptionalParam('skipVerification', 'Skip on-chain verification (use with caution)', false)
  .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
    const { ethers } = hre
    const chainId = hre.network.config.chainId ?? (await ethers.provider.getNetwork()).chainId
    const contractName = taskArgs.contract

    console.log('\n========== Sync Pending Implementation ==========\n')
    console.log(`Network: ${hre.network.name} (chainId=${chainId})`)
    console.log(`Contract: ${contractName}`)

    // Load address book
    const issuanceAddressBookPath = path.resolve(__dirname, '../../issuance/addresses.json')
    const addressBook = new EnhancedIssuanceAddressBook(issuanceAddressBookPath, Number(chainId))

    // Check if there's a pending implementation
    const pendingImpl = addressBook.getPendingImplementation(contractName as any)
    if (!pendingImpl) {
      throw new Error(`No pending implementation found for ${contractName}`)
    }

    console.log(`\n📋 Pending implementation: ${pendingImpl}`)

    // Step 1: Verify on-chain (unless skipped)
    if (!taskArgs.skipVerification) {
      console.log('\n🔍 Verifying on-chain implementation...')

      const entry = addressBook.getEntry(contractName as any)
      if (!entry || !entry.address) {
        throw new Error(`Contract ${contractName} not found in address book`)
      }

      const proxyAddress = entry.address

      // Get implementation address from proxy
      // EIP-1967 storage slot for implementation: keccak256("eip1967.proxy.implementation") - 1
      const implSlot = '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc'
      const implBytes = await ethers.provider.getStorage(proxyAddress, implSlot)
      const currentImpl = ethers.getAddress('0x' + implBytes.slice(-40))

      console.log(`   Proxy: ${proxyAddress}`)
      console.log(`   Current implementation (on-chain): ${currentImpl}`)
      console.log(`   Pending implementation (address book): ${pendingImpl}`)

      if (currentImpl.toLowerCase() !== pendingImpl.toLowerCase()) {
        throw new Error(
          `On-chain implementation (${currentImpl}) does not match pending (${pendingImpl}). ` +
            `Has governance executed the upgrade?`,
        )
      }

      console.log('✅ On-chain implementation matches pending implementation')
    } else {
      console.log('\n⚠️  Skipping on-chain verification (--skip-verification flag)')
    }

    // Step 2: Activate pending implementation
    console.log('\n📝 Updating address book...')

    addressBook.activatePendingImplementation(contractName as any)

    console.log('✅ Address book updated')
    console.log(`   ${contractName} implementation: ${pendingImpl}`)
    console.log(`   Pending implementation cleared`)

    // Summary
    console.log('\n========== Sync Complete ==========\n')
    console.log('📊 Summary:')
    console.log(`   Contract: ${contractName}`)
    console.log(`   New implementation: ${pendingImpl}`)
    console.log(`   Address book: ${issuanceAddressBookPath}`)
    console.log('\n✅ The address book now reflects the on-chain state')
  })
