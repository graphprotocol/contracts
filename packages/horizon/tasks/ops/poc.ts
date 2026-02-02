/**
 * Proof-of-concept task for validating fork testing with impersonated accounts
 *
 * This task validates that we can:
 * 1. Connect to a forked Arbitrum One chain
 * 2. Impersonate accounts (gateway sender, deployer)
 * 3. Read contract state
 * 4. Send transactions from impersonated accounts
 */

import { requireLocalNetwork } from '@graphprotocol/toolshed/hardhat'
import { task } from 'hardhat/config'
import type { HardhatRuntimeEnvironment } from 'hardhat/types'

import { DEFAULTS } from './lib/types'

// TAP Escrow v1 ABI (minimal for testing)
const TAP_ESCROW_ABI = [
  'function escrowAccounts(address sender, address receiver) external view returns (uint256 balance, uint256 amountThawing, uint256 thawEndTimestamp)',
  'function thaw(address receiver, uint256 amount) external',
  'function withdrawEscrowThawingPeriod() external view returns (uint256)',
]

task('ops:poc', 'Proof-of-concept: test fork and impersonation')
  .setAction(async (_, hre: HardhatRuntimeEnvironment) => {
    console.log('=== Fork & Impersonation POC ===\n')

    // Ensure we're on a local network (fork)
    requireLocalNetwork(hre)

    const chainId = (await hre.ethers.provider.getNetwork()).chainId
    console.log(`Connected to network: ${hre.network.name} (chainId: ${chainId})`)

    // Test 1: Read contract state from forked chain
    console.log('\n--- Test 1: Read forked chain state ---')

    const escrowContract = new hre.ethers.Contract(
      DEFAULTS.TAP_ESCROW,
      TAP_ESCROW_ABI,
      hre.ethers.provider,
    )

    const thawingPeriod = await escrowContract.withdrawEscrowThawingPeriod()
    console.log(`TAP Escrow thawing period: ${thawingPeriod} seconds (${Number(thawingPeriod) / 86400} days)`)

    // Use one of the known sender/receiver pairs
    const sender = DEFAULTS.SENDER_ADDRESSES[0]
    // Pick a known receiver - we'll query a few to find one with balance
    // For POC, let's just check if we can read the contract
    console.log(`Sender address: ${sender}`)

    // Test 2: Impersonate the gateway sender account
    console.log('\n--- Test 2: Impersonate gateway sender ---')

    const gatewaySigner = await hre.ethers.getImpersonatedSigner(sender)
    console.log(`Impersonated signer address: ${gatewaySigner.address}`)

    // Fund the impersonated account with ETH for gas
    const [funder] = await hre.ethers.getSigners()
    console.log(`Funding from: ${funder.address}`)

    const fundTx = await funder.sendTransaction({
      to: sender,
      value: hre.ethers.parseEther('1.0'),
    })
    await fundTx.wait()
    console.log(`Funded ${sender} with 1 ETH`)

    const balance = await hre.ethers.provider.getBalance(sender)
    console.log(`Gateway sender ETH balance: ${hre.ethers.formatEther(balance)} ETH`)

    // Test 3: Try to call a view function with the impersonated account
    console.log('\n--- Test 3: Call contract as impersonated account ---')

    const escrowWithSigner = escrowContract.connect(gatewaySigner)

    // Let's try to read an escrow account state
    // We need a real receiver address - let's use the upgrade indexer as a test
    const testReceiver = DEFAULTS.UPGRADE_INDEXER
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const escrowState = await (escrowWithSigner as any).escrowAccounts(sender, testReceiver)
    console.log(`Escrow state for sender=${sender.slice(0, 10)}... receiver=${testReceiver.slice(0, 10)}...`)
    console.log(`  Balance: ${hre.ethers.formatEther(escrowState.balance)} GRT`)
    console.log(`  Amount Thawing: ${hre.ethers.formatEther(escrowState.amountThawing)} GRT`)
    console.log(`  Thaw End Timestamp: ${escrowState.thawEndTimestamp}`)

    // Test 4: Try to send a state-changing transaction (if there's balance)
    console.log('\n--- Test 4: Send state-changing transaction ---')

    if (escrowState.balance > 0n && escrowState.balance > escrowState.amountThawing) {
      const amountToThaw = escrowState.balance - escrowState.amountThawing
      console.log(`Attempting to thaw ${hre.ethers.formatEther(amountToThaw)} GRT...`)

      try {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const tx = await (escrowWithSigner as any).thaw(testReceiver, amountToThaw)
        const receipt = await tx.wait()
        console.log(`Thaw transaction successful!`)
        console.log(`  TX Hash: ${receipt.hash}`)
        console.log(`  Gas Used: ${receipt.gasUsed}`)

        // Verify state changed
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const newState = await (escrowWithSigner as any).escrowAccounts(sender, testReceiver)
        console.log(`\nNew escrow state:`)
        console.log(`  Amount Thawing: ${hre.ethers.formatEther(newState.amountThawing)} GRT`)
        console.log(`  Thaw End Timestamp: ${newState.thawEndTimestamp}`)
        console.log(`  Thaw End Date: ${new Date(Number(newState.thawEndTimestamp) * 1000).toISOString()}`)
      } catch (error) {
        console.log(`Thaw transaction failed (this might be expected if no balance): ${error}`)
      }
    } else {
      console.log(`No thawable balance for this sender/receiver pair.`)
      console.log(`This is fine - we verified we can read state and impersonate accounts.`)

      // Let's try a simpler test - just verify we CAN send a transaction
      // by doing a simple ETH transfer back
      console.log(`\nTrying simple ETH transfer to verify tx sending works...`)
      const simpleTx = await gatewaySigner.sendTransaction({
        to: funder.address,
        value: hre.ethers.parseEther('0.1'),
      })
      const simpleReceipt = await simpleTx.wait()
      console.log(`Simple transfer successful! TX: ${simpleReceipt?.hash}`)
    }

    // Test 5: Test time manipulation
    console.log('\n--- Test 5: Time manipulation ---')

    const blockBefore = await hre.ethers.provider.getBlock('latest')
    console.log(`Current block timestamp: ${blockBefore?.timestamp} (${new Date((blockBefore?.timestamp || 0) * 1000).toISOString()})`)

    // Advance time by 30 days
    const thirtyDays = 30 * 24 * 60 * 60
    await hre.network.provider.send('evm_increaseTime', [thirtyDays])
    await hre.network.provider.send('evm_mine')

    const blockAfter = await hre.ethers.provider.getBlock('latest')
    console.log(`After advancing 30 days: ${blockAfter?.timestamp} (${new Date((blockAfter?.timestamp || 0) * 1000).toISOString()})`)

    console.log('\n=== All POC tests passed! ===')
    console.log('\nValidated:')
    console.log('  - Can connect to forked Arbitrum One')
    console.log('  - Can read contract state from fork')
    console.log('  - Can impersonate accounts')
    console.log('  - Can fund impersonated accounts')
    console.log('  - Can send transactions from impersonated accounts')
    console.log('  - Can manipulate time (evm_increaseTime)')
  })
