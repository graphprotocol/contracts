import type { Environment } from '@rocketh/core/types'
import fs from 'fs'
import path from 'path'
import { createPublicClient, createWalletClient, custom, http, parseEther } from 'viem'
import { privateKeyToAccount } from 'viem/accounts'

import { getForkNetwork, getForkStateDir, getTargetChainIdFromEnv, isForkMode } from './address-book-utils.js'
import { getGovernor } from './controller-utils.js'
import type { BuilderTx } from './tx-builder.js'
import { TxBuilder } from './tx-builder.js'

/**
 * Convert network name to env var prefix: arbitrumSepolia → ARBITRUM_SEPOLIA
 */
function networkToEnvPrefix(networkName: string): string {
  return networkName.replace(/([a-z])([A-Z])/g, '$1_$2').toUpperCase()
}

interface SafeTxBatch {
  version: string
  chainId: string
  createdAt: number
  meta?: unknown
  transactions: BuilderTx[]
}

/**
 * Get governance TX directory path
 *
 * In fork mode: fork/<networkName>/<FORK_NETWORK>/txs/
 * In normal mode: txs/<networkName>/
 *
 * Stored outside deployments/ so rocketh manages its own directory cleanly.
 *
 * @param networkName - Network name (e.g., 'fork', 'localhost', 'arbitrumSepolia')
 */
export function getGovernanceTxDir(networkName: string): string {
  const forkNetwork = getForkNetwork()
  if (forkNetwork) {
    return path.join(getForkStateDir(networkName, forkNetwork), 'txs')
  }
  return path.resolve(process.cwd(), 'txs', networkName)
}

/**
 * Count pending governance TX batch files
 *
 * @param networkName - Network name (e.g., 'fork', 'arbitrumSepolia')
 */
export function countPendingGovernanceTxs(networkName: string): number {
  const txDir = getGovernanceTxDir(networkName)
  if (!fs.existsSync(txDir)) {
    return 0
  }
  return fs.readdirSync(txDir).filter((f) => f.endsWith('.json') && !f.startsWith('.')).length
}

/**
 * Check if a specific governance TX file exists
 *
 * @param networkName - Network name (e.g., 'fork', 'arbitrumSepolia')
 * @param name - TX file name (without .json extension)
 */
export function hasGovernanceTx(networkName: string, name: string): boolean {
  const txFile = path.join(getGovernanceTxDir(networkName), `${name}.json`)
  return fs.existsSync(txFile)
}

/**
 * Check for pending upgrade TX and exit if found
 *
 * Standard pattern for contract "ready" steps that depend on governance execution.
 * Call this at the start of the final deploy step for any upgradeable contract.
 *
 * @param env - Deployment environment
 * @param contractName - Contract name (used to derive TX filename: upgrade-{contractName})
 */
export function requireUpgradeExecuted(env: Environment, contractName: string): void {
  const txName = `upgrade-${contractName}`
  if (hasGovernanceTx(env.name, txName)) {
    const txFile = path.join(getGovernanceTxDir(env.name), `${txName}.json`)
    env.showMessage(`\n⏳ ${contractName} pending governance (${txFile})`)
    env.showMessage(`   Run: npx hardhat deploy:execute-governance --network ${env.name}`)
    process.exit(1)
  }
}

/**
 * Create a TxBuilder configured for governance transactions
 *
 * Standard pattern for creating governance TX builders with correct:
 * - Target chain ID (handles fork mode)
 * - Output directory (handles fork mode)
 * - Template path (uses default)
 *
 * @param env - Deployment environment
 * @param name - TX batch name (without .json extension)
 * @param meta - Optional metadata for the TX batch
 * @returns Configured TxBuilder instance
 */
export async function createGovernanceTxBuilder(
  env: Environment,
  name: string,
  meta?: { name?: string; description?: string },
): Promise<TxBuilder> {
  const targetChainId = await getTargetChainIdFromEnv(env)
  const outputDir = getGovernanceTxDir(env.name)

  return new TxBuilder(targetChainId, {
    outputDir,
    name,
    meta,
  })
}

/**
 * Save governance TX batch and exit with code 1
 *
 * Standard completion pattern for scripts that generate governance TX batches.
 * This function:
 * 1. Saves the TX batch to file
 * 2. Displays appropriate messages
 * 3. Exits with code 1 to prevent subsequent deployment steps
 *
 * @param env - Deployment environment
 * @param builder - TX builder with batched transactions
 * @param contractName - Optional contract name for contextual message (e.g., "IssuanceAllocator activation")
 * @returns Never returns (exits process)
 */
export function saveGovernanceTxAndExit(
  env: Environment,
  builder: { saveToFile: () => string },
  contractName?: string,
): never {
  const txFile = builder.saveToFile()
  env.showMessage(`\n✓ TX batch saved: ${txFile}`)

  env.showMessage('\n📋 GOVERNANCE ACTION REQUIRED:')
  if (contractName) {
    env.showMessage(`   ${contractName} requires governance execution`)
  }
  env.showMessage(`   TX batch: ${txFile}`)
  env.showMessage('\nNext steps:')
  env.showMessage('   1. Execute governance TX (see options below)')
  env.showMessage('   2. Run: npx hardhat deploy --tags sync --network ' + env.name)
  env.showMessage('   3. Continue deployment')
  env.showMessage('\nExecution options:')
  env.showMessage('   • Fork testing: npx hardhat deploy:execute-governance --network fork')
  env.showMessage('   • EOA governor: Set GOVERNOR_PRIVATE_KEY and run deploy:execute-governance')
  env.showMessage('   • Safe multisig: https://app.safe.global/ → Transaction Builder → Upload JSON')
  env.showMessage('\nSee: packages/deployment/docs/GovernanceWorkflow.md\n')

  // Exit with code 1 to prevent subsequent steps from running until governance TX is executed
  // This is expected prerequisite state, not an error
  process.exit(1)
}

/**
 * Execute a TX builder batch directly and save to executed/ folder
 *
 * Use this when the caller has authority to execute (e.g., deployer has GOVERNOR_ROLE).
 * This maintains the consistent pattern of ALWAYS creating a TX batch, but executing
 * it inline when possible.
 *
 * @param env - Deployment environment
 * @param builder - TX builder with batched transactions
 * @param account - Account to execute from (deployer address)
 * @returns Number of transactions executed
 */
export async function executeTxBatchDirect(env: Environment, builder: TxBuilder, account: string): Promise<number> {
  const transactions = builder.getTransactions()
  if (transactions.length === 0) {
    return 0
  }

  // Create viem clients
  const publicClient = createPublicClient({
    transport: custom(env.network.provider),
  })
  const walletClient = createWalletClient({
    transport: custom(env.network.provider),
  })

  // Execute each transaction
  for (let i = 0; i < transactions.length; i++) {
    const tx = transactions[i]
    env.showMessage(`      ${i + 1}/${transactions.length} TX to ${tx.to.slice(0, 10)}...`)

    const hash = await walletClient.sendTransaction({
      chain: null,
      account: account as `0x${string}`,
      to: tx.to as `0x${string}`,
      data: tx.data as `0x${string}`,
      value: BigInt(tx.value),
    })
    await publicClient.waitForTransactionReceipt({ hash })
    env.showMessage(`      ✓ TX hash: ${hash}`)
  }

  // Save to executed/ folder for audit trail
  const txDir = getGovernanceTxDir(env.name)
  const executedDir = path.join(txDir, 'executed')
  if (!fs.existsSync(executedDir)) {
    fs.mkdirSync(executedDir, { recursive: true })
  }

  // Save with original filename in executed/
  const originalFile = builder.outputFile
  const filename = path.basename(originalFile)
  const executedFile = path.join(executedDir, filename)
  fs.writeFileSync(executedFile, JSON.stringify({ transactions }, null, 2) + '\n')
  env.showMessage(`      ✓ Saved to ${executedFile}`)

  return transactions.length
}

export interface ExecuteGovernanceOptions {
  /** Optional TX batch name filter */
  name?: string
  /** Governor private key (from keystore or env var) */
  governorPrivateKey?: string
}

export async function executeGovernanceTxs(env: Environment, options?: ExecuteGovernanceOptions): Promise<number> {
  const { name, governorPrivateKey } = options ?? {}
  // Determine TX directory - in fork mode, also check source network's TX directory
  const forkNetwork = getForkNetwork()
  let txDir = getGovernanceTxDir(env.name)
  let sourceNetworkFallback = false

  if (
    !fs.existsSync(txDir) ||
    fs.readdirSync(txDir).filter((f) => f.endsWith('.json') && !f.startsWith('.')).length === 0
  ) {
    // Fork-state directory empty - check source network's TX directory
    if (forkNetwork) {
      const sourceNetworkTxDir = path.resolve(process.cwd(), 'txs', forkNetwork)
      if (
        fs.existsSync(sourceNetworkTxDir) &&
        fs.readdirSync(sourceNetworkTxDir).filter((f) => f.endsWith('.json') && !f.startsWith('.')).length > 0
      ) {
        txDir = sourceNetworkTxDir
        sourceNetworkFallback = true
        env.showMessage(`\n📂 Using source network TXs: ${txDir}`)
      }
    }
  }

  if (!fs.existsSync(txDir)) {
    env.showMessage(`\n✓ No governance TXs directory: ${txDir}`)
    if (forkNetwork) {
      env.showMessage(`   (Also checked: txs/${forkNetwork}/)`)
    }
    return 0
  }

  // Find pending TX batch files (optionally filtered by name)
  let files: string[]
  if (name) {
    const specificFile = `${name}.json`
    files = fs.existsSync(path.join(txDir, specificFile)) ? [specificFile] : []
  } else {
    files = fs.readdirSync(txDir).filter((f) => f.endsWith('.json') && !f.startsWith('.'))
  }
  if (files.length === 0) {
    env.showMessage(`\n✓ No pending governance TXs`)
    if (forkNetwork && !sourceNetworkFallback) {
      env.showMessage(`   (Also checked: txs/${forkNetwork}/)`)
    }
    return 0
  }

  // Get governor address from Controller
  const governor = (await getGovernor(env)) as `0x${string}`

  // Create viem client for checking governor type
  const publicClient = createPublicClient({
    transport: custom(env.network.provider),
  })

  // Check if in fork mode
  const inForkMode = isForkMode()

  if (!inForkMode) {
    // Not in fork mode - check if governor is EOA or Safe
    const governorCode = await publicClient.getCode({ address: governor })
    const isContract = governorCode && governorCode !== '0x'

    // Governor private key passed from task (resolved from keystore or env var)

    if (isContract) {
      // Governor is a Safe multisig - require Safe UI workflow
      env.showMessage(`\n📋 Safe multisig governance execution required`)
      env.showMessage(`   Governor address: ${governor}`)
      env.showMessage(`\nExecute via Safe Transaction Builder:`)
      env.showMessage(`\n1. Go to https://app.safe.global/`)
      env.showMessage(`   - Connect wallet`)
      env.showMessage(`   - Select the governor Safe (${governor})`)
      env.showMessage(`   - Navigate to: Apps → Transaction Builder`)
      env.showMessage(`\n2. Click "Upload a JSON" and select:`)
      for (const file of files) {
        env.showMessage(`   - ${path.join(txDir, file)}`)
      }
      env.showMessage(`\n3. Review decoded transactions`)
      env.showMessage(`4. Create batch → Collect signatures → Execute`)
      env.showMessage(`\n5. After on-chain execution, sync address books:`)
      env.showMessage(`   npx hardhat deploy --tags sync --network ${env.name}`)
      env.showMessage(`\nNote: If Safe is not available on ${env.name}, test in fork mode:`)
      env.showMessage(`   FORK_NETWORK=arbitrumOne npx hardhat deploy:execute-governance --network fork\n`)
      return 0
    }

    // Governor is an EOA
    if (!governorPrivateKey) {
      const keyName = `${networkToEnvPrefix(env.name)}_GOVERNOR_KEY`
      env.showMessage(`\n❌ Cannot execute governance TXs on ${env.name}`)
      env.showMessage(`   Governor address: ${governor} (EOA)`)
      env.showMessage(`\nTo execute with EOA private key:`)
      env.showMessage(`   npx hardhat keystore set ${keyName}`)
      env.showMessage(`   npx hardhat deploy:execute-governance --network ${env.name}`)
      env.showMessage(`\nOr via environment variable:`)
      env.showMessage(`   export ${keyName}=0x...`)
      env.showMessage(`\nTo test with Safe Transaction Builder (validation only):`)
      env.showMessage(`   1. Go to https://app.safe.global/`)
      env.showMessage(`   2. Apps → Transaction Builder → Upload JSON`)
      env.showMessage(`   3. Select: ${path.join(txDir, files[0])}`)
      env.showMessage(`   4. Review decoded transactions (don't execute)`)
      env.showMessage(`\nOr test in fork mode:`)
      env.showMessage(`   FORK_NETWORK=${env.name} npx hardhat deploy:execute-governance --network fork\n`)
      return 0
    }

    // Have private key - execute as EOA
    env.showMessage(`\n🔓 Executing ${files.length} governance TX batch(es)...`)
    env.showMessage(`   Governor: ${governor} (EOA)`)
    return await executeWithEOA(env, publicClient, files, txDir, governorPrivateKey)
  }

  // Fork mode - use impersonation
  env.showMessage(`\n🔓 Executing ${files.length} governance TX batch(es) via impersonation...`)
  env.showMessage(`   (Fork mode - impersonating governor for testing)`)
  env.showMessage(`   Governor: ${governor}`)
  return await executeWithImpersonation(env, publicClient, files, txDir, governor)
}

/**
 * Execute governance TXs using EOA private key (testnet with EOA governor)
 */
async function executeWithEOA(
  env: Environment,
  publicClient: ReturnType<typeof createPublicClient>,
  files: string[],
  txDir: string,
  privateKey: string,
): Promise<number> {
  // Create wallet from private key
  const account = privateKeyToAccount(privateKey as `0x${string}`)

  // Create wallet client with the account
  const walletClient = createWalletClient({
    account,
    transport: custom(env.network.provider),
  })

  let executedCount = 0
  const executedDir = path.join(txDir, 'executed')

  for (const file of files) {
    const filePath = path.join(txDir, file)
    env.showMessage(`\n   📋 ${file}`)

    try {
      const batchContents = fs.readFileSync(filePath, 'utf8')
      const batch: SafeTxBatch = JSON.parse(batchContents)

      // Execute each transaction
      for (let i = 0; i < batch.transactions.length; i++) {
        const tx = batch.transactions[i]
        env.showMessage(`      ${i + 1}/${batch.transactions.length} TX to ${tx.to.slice(0, 10)}...`)

        const hash = await walletClient.sendTransaction({
          chain: null,
          to: tx.to as `0x${string}`,
          data: tx.data as `0x${string}`,
          value: BigInt(tx.value),
        })
        await publicClient.waitForTransactionReceipt({ hash })
        env.showMessage(`      ✓ TX hash: ${hash}`)
      }

      // Move to executed directory
      if (!fs.existsSync(executedDir)) {
        fs.mkdirSync(executedDir, { recursive: true })
      }
      fs.renameSync(filePath, path.join(executedDir, file))
      env.showMessage(`      ✓ Executed and moved to executed/`)
      executedCount++
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      env.showMessage(`      ✗ Failed: ${errorMessage.slice(0, 80)}...`)
      throw error
    }
  }

  env.showMessage(`\n✅ Executed ${executedCount} governance TX batch(es)`)
  return executedCount
}

/**
 * Execute governance TXs using impersonation (fork mode only)
 */
async function executeWithImpersonation(
  env: Environment,
  publicClient: ReturnType<typeof createPublicClient>,
  files: string[],
  txDir: string,
  governor: `0x${string}`,
): Promise<number> {
  const walletClient = createWalletClient({
    transport: custom(env.network.provider),
  })

  // Use provider.request for hardhat-specific RPC methods
  const request = env.network.provider.request.bind(env.network.provider) as (args: {
    method: string
    params: unknown[]
  }) => Promise<unknown>

  // Impersonate governor
  await request({
    method: 'hardhat_impersonateAccount',
    params: [governor],
  })

  // Fund governor with ETH for gas
  const tenEth = '0x' + parseEther('10').toString(16)
  await request({
    method: 'hardhat_setBalance',
    params: [governor, tenEth],
  })

  let executedCount = 0
  const executedDir = path.join(txDir, 'executed')

  for (const file of files) {
    const filePath = path.join(txDir, file)
    env.showMessage(`\n   📋 ${file}`)

    try {
      const batchContents = fs.readFileSync(filePath, 'utf8')
      const batch: SafeTxBatch = JSON.parse(batchContents)

      // Execute each transaction
      for (let i = 0; i < batch.transactions.length; i++) {
        const tx = batch.transactions[i]
        env.showMessage(`      ${i + 1}/${batch.transactions.length} TX to ${tx.to.slice(0, 10)}...`)

        const hash = await walletClient.sendTransaction({
          chain: null,
          account: governor,
          to: tx.to as `0x${string}`,
          data: tx.data as `0x${string}`,
          value: BigInt(tx.value),
        })
        await publicClient.waitForTransactionReceipt({ hash })
      }

      // Move to executed directory
      if (!fs.existsSync(executedDir)) {
        fs.mkdirSync(executedDir, { recursive: true })
      }
      fs.renameSync(filePath, path.join(executedDir, file))
      env.showMessage(`      ✓ Executed and moved to executed/`)
      executedCount++
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      env.showMessage(`      ✗ Failed: ${errorMessage.slice(0, 80)}...`)
      throw error
    }
  }

  // Stop impersonating
  await request({
    method: 'hardhat_stopImpersonatingAccount',
    params: [governor],
  })

  env.showMessage(`\n✅ Executed ${executedCount} governance TX batch(es)`)
  return executedCount
}
