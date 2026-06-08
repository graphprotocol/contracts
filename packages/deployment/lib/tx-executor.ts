import fs from 'fs'

import type { BuilderTx } from '../lib/tx-builder.js'

interface SafeTxBatch {
  version: string
  chainId: string
  createdAt: number
  meta?: unknown
  transactions: BuilderTx[]
}

// Extended HRE with ethers and network plugins
interface ExtendedHRE {
  ethers: {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    getSigner: (address: string) => Promise<any>
  }
  network: {
    provider: {
      request: (args: { method: string; params: unknown[] }) => Promise<unknown>
      send: (method: string, params: unknown[]) => Promise<unknown>
    }
  }
}

/**
 * Execute Safe Transaction Builder JSON batches via impersonated governance
 *
 * This utility allows tests to execute the same TX batches that will be sent
 * to governance in production, ensuring end-to-end validation.
 *
 * Usage in tests:
 * ```typescript
 * // 1. Generate TX batch (same as production)
 * const result = await buildRewardsEligibilityUpgradeTxs(hre, params)
 *
 * // 2. Execute via impersonation (test only)
 * const executor = new GovernanceTxExecutor(hre)
 * await executor.executeBatch(result.outputFile, governorAddress)
 *
 * // 3. Verify integration (same as production)
 * await run('deploy:verify-integration')
 * ```
 */
export class GovernanceTxExecutor {
  private extHre: ExtendedHRE

  constructor(hre: unknown) {
    this.extHre = hre as ExtendedHRE
  }

  /**
   * Execute Safe TX Builder JSON batch via impersonated governance account
   *
   * This simulates governance execution in a test environment by:
   * 1. Parsing the Safe TX Builder JSON file
   * 2. Impersonating the governor address
   * 3. Funding the governor with ETH for gas
   * 4. Executing each transaction in sequence
   * 5. Stopping impersonation
   *
   * @param txBatchFile - Path to Safe TX Builder JSON file
   * @param governorAddress - Address to impersonate as governor
   * @throws Error if any transaction fails
   */
  async executeBatch(txBatchFile: string, governorAddress: string): Promise<void> {
    const { ethers } = this.extHre

    // 1. Parse Safe TX Builder JSON
    const batchContents = fs.readFileSync(txBatchFile, 'utf8')
    const batch: SafeTxBatch = JSON.parse(batchContents)

    console.log(`\n📋 Executing TX batch from: ${txBatchFile}`)
    console.log(`   Chain ID: ${batch.chainId}`)
    console.log(`   Transactions: ${batch.transactions.length}`)
    console.log(`   Governor: ${governorAddress}\n`)

    // 2. Impersonate governor
    await this.extHre.network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [governorAddress],
    })

    // 3. Fund governor with ETH for gas
    await this.extHre.network.provider.send('hardhat_setBalance', [
      governorAddress,
      '0x56BC75E2D63100000', // 100 ETH
    ])

    // 4. Execute each transaction in batch
    const governor = await ethers.getSigner(governorAddress)

    for (let i = 0; i < batch.transactions.length; i++) {
      const tx = batch.transactions[i]
      console.log(`   ${i + 1}/${batch.transactions.length} Executing TX to ${tx.to}...`)

      try {
        const receipt = await governor.sendTransaction({
          to: tx.to,
          data: tx.data,
          value: tx.value,
        })

        await receipt.wait()
        console.log(`      ✓ Success (gas: ${receipt.gasLimit})`)
      } catch (error: unknown) {
        console.error(`      ✗ Failed: ${error instanceof Error ? error.message : String(error)}`)
        throw new Error(`Transaction ${i + 1} failed: ${error instanceof Error ? error.message : String(error)}`)
      }
    }

    // 5. Stop impersonation
    await this.extHre.network.provider.request({
      method: 'hardhat_stopImpersonatingAccount',
      params: [governorAddress],
    })

    console.log(`\n✅ All ${batch.transactions.length} transactions executed successfully\n`)
  }

  /**
   * Parse Safe TX Builder JSON without executing
   *
   * Useful for validation and inspection of TX batches
   *
   * @param txBatchFile - Path to Safe TX Builder JSON file
   * @returns Parsed Safe TX batch
   */
  parseBatch(txBatchFile: string): SafeTxBatch {
    const batchContents = fs.readFileSync(txBatchFile, 'utf8')
    return JSON.parse(batchContents) as SafeTxBatch
  }
}
