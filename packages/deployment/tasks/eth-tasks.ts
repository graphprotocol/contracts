import { task } from 'hardhat/config'
import { ArgumentType } from 'hardhat/types/arguments'
import type { NewTaskActionFunction } from 'hardhat/types/tasks'
import { createPublicClient, createWalletClient, custom, formatEther, parseEther, type PublicClient } from 'viem'
import { privateKeyToAccount } from 'viem/accounts'

import { getDeployerKeyName, resolveConfigVar } from '../lib/task-utils.js'

// -- Task Types --

interface CheckKeyArgs {
  key: string
}

interface FundArgs {
  to: string
  amount: string
}

interface BalanceArgs {
  account: string
}

// -- Task Actions --

/**
 * Verify a keystore variable holds the private key for an expected address
 */
const checkKeyAction: NewTaskActionFunction<CheckKeyArgs> = async (taskArgs, hre) => {
  if (!taskArgs.key) {
    console.error('\nError: --key is required')
    console.error('Usage: npx hardhat eth:check-key --key ARBITRUM_ONE_ORACLE_KEY')
    return
  }

  const keyValue = await resolveConfigVar(hre, taskArgs.key)

  if (!keyValue) {
    console.error(`\nError: Key "${taskArgs.key}" not found in keystore or environment.`)
    console.error(`Set via keystore: npx hardhat keystore set ${taskArgs.key}`)
    console.error(`Or environment: export ${taskArgs.key}=0x...`)
    return
  }

  const account = privateKeyToAccount(keyValue as `0x${string}`)

  console.log(`\nKey Check`)
  console.log(`  Variable: ${taskArgs.key}`)
  console.log(`  Address:  ${account.address}`)
  console.log()
}

/**
 * Query ETH balance for an address
 */
const balanceAction: NewTaskActionFunction<BalanceArgs> = async (taskArgs, hre) => {
  if (!taskArgs.account) {
    console.error('\nError: --account is required')
    console.error('Usage: npx hardhat eth:balance --account 0x... --network arbitrumOne')
    return
  }
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const conn = await (hre as any).network.connect()
  const networkName = conn.networkName

  const client = createPublicClient({
    transport: custom(conn.provider),
  }) as PublicClient

  const chainId = await client.getChainId()
  const account = taskArgs.account as `0x${string}`
  const balance = await client.getBalance({ address: account })

  console.log(`\nETH Balance`)
  console.log(`  Account: ${account}`)
  console.log(`  Network: ${networkName} (chainId: ${chainId})`)
  console.log(`  Balance: ${formatEther(balance)} ETH`)
  console.log()
}

/**
 * Send ETH from deployer to an address
 */
const fundAction: NewTaskActionFunction<FundArgs> = async (taskArgs, hre) => {
  if (!taskArgs.to || !taskArgs.amount) {
    console.error('\nError: --to and --amount are required')
    console.error('Usage: npx hardhat eth:fund --to 0x... --amount 0.01 --network arbitrumOne')
    return
  }
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const conn = await (hre as any).network.connect()
  const networkName = conn.networkName

  const client = createPublicClient({
    transport: custom(conn.provider),
  }) as PublicClient

  const chainId = await client.getChainId()

  // Get deployer key
  const keyName = getDeployerKeyName(networkName)
  const deployerKey = await resolveConfigVar(hre, keyName)

  if (!deployerKey) {
    console.error('\nError: No deployer key configured.')
    console.error(`Set via keystore: npx hardhat keystore set ${keyName}`)
    console.error(`Or environment: export ${keyName}=0x...`)
    return
  }

  const account = privateKeyToAccount(deployerKey as `0x${string}`)
  const to = taskArgs.to as `0x${string}`
  const value = parseEther(taskArgs.amount)

  // Check deployer balance
  const balance = await client.getBalance({ address: account.address })

  if (balance < value) {
    console.error(`\nError: Insufficient balance`)
    console.error(`  Deployer balance: ${formatEther(balance)} ETH`)
    console.error(`  Requested:        ${taskArgs.amount} ETH`)
    return
  }

  console.log(`\nSending ETH`)
  console.log(`  From:    ${account.address}`)
  console.log(`  To:      ${to}`)
  console.log(`  Amount:  ${taskArgs.amount} ETH`)
  console.log(`  Network: ${networkName} (chainId: ${chainId})`)

  const walletClient = createWalletClient({
    account,
    transport: custom(conn.provider),
  })

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const hash = await (walletClient as any).sendTransaction({ to, value })
  console.log(`  TX:      ${hash}`)

  const receipt = await client.waitForTransactionReceipt({ hash })
  if (receipt.status === 'success') {
    const newBalance = await client.getBalance({ address: to })
    console.log(`\n  Sent successfully!`)
    console.log(`  Recipient balance: ${formatEther(newBalance)} ETH\n`)
  } else {
    console.error(`\n  Transaction failed\n`)
  }
}

// -- Task Definitions --

/**
 * Verify a keystore/env variable holds the key for an expected address
 *
 * Examples:
 *   npx hardhat eth:check-key --key ARBITRUM_ONE_ORACLE_KEY
 */
export const ethCheckKeyTask = task('eth:check-key', 'Derive and display address from a keystore variable')
  .addOption({
    name: 'key',
    description: 'Keystore variable name (e.g. ARBITRUM_ONE_ORACLE_KEY)',
    type: ArgumentType.STRING,
    defaultValue: '',
  })
  .setAction(async () => ({ default: checkKeyAction }))
  .build()

/**
 * Query ETH balance for an address
 *
 * Examples:
 *   npx hardhat eth:balance --account 0x1234... --network arbitrumOne
 */
export const ethBalanceTask = task('eth:balance', 'Query ETH balance for an address')
  .addOption({
    name: 'account',
    description: 'Address to query balance for',
    type: ArgumentType.STRING,
    defaultValue: '',
  })
  .setAction(async () => ({ default: balanceAction }))
  .build()

/**
 * Send ETH from deployer to an address
 *
 * Uses the deployer key from the Hardhat keystore or environment.
 *
 * Examples:
 *   npx hardhat eth:fund --to 0x1234... --amount 0.01 --network arbitrumOne
 */
export const ethFundTask = task('eth:fund', 'Send ETH from deployer to an address')
  .addOption({
    name: 'to',
    description: 'Recipient address',
    type: ArgumentType.STRING,
    defaultValue: '',
  })
  .addOption({
    name: 'amount',
    description: 'Amount of ETH to send (e.g. 0.01)',
    type: ArgumentType.STRING,
    defaultValue: '',
  })
  .setAction(async () => ({ default: fundAction }))
  .build()

export default [ethCheckKeyTask, ethBalanceTask, ethFundTask]
