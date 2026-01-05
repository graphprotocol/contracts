import { task } from 'hardhat/config'
import type { HardhatRuntimeEnvironment } from 'hardhat/types'
import { connectGraphHorizon, connectGraphIssuance } from '@graphprotocol/toolshed/deployments'

/**
 * Verify issuance contract integration status
 *
 * This task verifies that governance has executed integration steps by checking
 * on-chain state. Replaces Ignition checkpoint modules with hardhat task.
 *
 * Verifications:
 * - REO integrated: RewardsManager.rewardsEligibilityOracle() == REO address
 * - IA integrated: RewardsManager.issuanceAllocator() == IA address
 * - IA has minter role: GraphToken hasRole(MINTER_ROLE, IA)
 *
 * Usage:
 *   npx hardhat issuance:verify-integration --network arbitrumOne
 *   npx hardhat issuance:verify-integration --check reo --network arbitrumSepolia
 *   npx hardhat issuance:verify-integration --check ia --network arbitrumOne
 */
task('issuance:verify-integration', 'Verify issuance contract integration with RewardsManager')
  .addOptionalParam('check', 'Specific check: reo, ia, ia-minter, or all', 'all')
  .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
    const { ethers } = hre
    const chainId = Number(hre.network.config.chainId ?? (await ethers.provider.getNetwork()).chainId)
    const checkType = taskArgs.check.toLowerCase()

    console.log('\n========== Integration Verification ==========\n')
    console.log(`Network: ${hre.network.name} (chainId=${chainId})`)
    console.log(`Check: ${checkType}\n`)

    // Load contracts from address books
    // Note: Using 'as any' to bypass incomplete type definitions in toolshed
    const horizon = connectGraphHorizon(chainId, ethers.provider) as any
    const issuance = connectGraphIssuance(chainId, ethers.provider) as any

    let allPassed = true

    // Verify REO integration
    if (checkType === 'all' || checkType === 'reo') {
      console.log('📋 Checking RewardsEligibilityOracle integration...')
      try {
        const currentREO = await horizon.RewardsManager.rewardsEligibilityOracle()
        const expectedREO = await issuance.RewardsEligibilityOracle.getAddress()

        if (currentREO.toLowerCase() === expectedREO.toLowerCase()) {
          console.log(`  ✅ REO integrated: ${currentREO}`)
        } else {
          console.log(`  ❌ REO NOT integrated`)
          console.log(`     Expected: ${expectedREO}`)
          console.log(`     Actual:   ${currentREO}`)
          allPassed = false
        }
      } catch (error: any) {
        console.log(`  ❌ Error checking REO: ${error.message}`)
        allPassed = false
      }
      console.log()
    }

    // Verify IA integration
    if (checkType === 'all' || checkType === 'ia') {
      console.log('📋 Checking IssuanceAllocator integration...')
      try {
        const currentIA = await horizon.RewardsManager.issuanceAllocator()
        const expectedIA = await issuance.IssuanceAllocator.getAddress()

        if (currentIA.toLowerCase() === expectedIA.toLowerCase()) {
          console.log(`  ✅ IA integrated: ${currentIA}`)
        } else {
          console.log(`  ❌ IA NOT integrated`)
          console.log(`     Expected: ${expectedIA}`)
          console.log(`     Actual:   ${currentIA}`)
          allPassed = false
        }
      } catch (error: any) {
        console.log(`  ❌ Error checking IA: ${error.message}`)
        allPassed = false
      }
      console.log()
    }

    // Verify IA minter role
    if (checkType === 'all' || checkType === 'ia-minter') {
      console.log('📋 Checking IssuanceAllocator minter role...')
      try {
        const iaAddress = await issuance.IssuanceAllocator.getAddress()
        const minterRole = await horizon.GraphToken.MINTER_ROLE()
        const hasMinterRole = await horizon.GraphToken.hasRole(minterRole, iaAddress)

        if (hasMinterRole) {
          console.log(`  ✅ IA has MINTER_ROLE`)
        } else {
          console.log(`  ❌ IA does NOT have MINTER_ROLE`)
          console.log(`     IA address: ${iaAddress}`)
          allPassed = false
        }
      } catch (error: any) {
        console.log(`  ❌ Error checking minter role: ${error.message}`)
        allPassed = false
      }
      console.log()
    }

    // Summary
    if (allPassed) {
      console.log('✅ All integration checks passed\n')
      process.exit(0)
    } else {
      console.log('❌ Some integration checks failed\n')
      console.log('Governance transactions may not have been executed yet.')
      console.log('Use `npx hardhat issuance:build-*-upgrade` to generate TX batches.\n')
      process.exit(1)
    }
  })
