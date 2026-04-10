import { task } from 'hardhat/config'
import { ArgumentType } from 'hardhat/types/arguments'
import type { NewTaskActionFunction } from 'hardhat/types/tasks'
import { createPublicClient, createWalletClient, custom, formatEther, parseEther, type PublicClient } from 'viem'
import { privateKeyToAccount } from 'viem/accounts'

import { GRAPH_TOKEN_ABI } from '../lib/abis.js'
import { getDeployerKeyName, resolveConfigVar } from '../lib/task-utils.js'
import { graph } from '../rocketh/deploy.js'

// governor() is on the Governed base contract, not in IGraphToken
const GOVERNED_ABI = [
  {
    inputs: [],
    name: 'governor',
    outputs: [{ type: 'address' }],
    stateMutability: 'view',
    type: 'function',
  },
] as const

/**
 * Get L2GraphToken address from horizon address book
 */
function getGraphTokenAddress(chainId: number): string | null {
  const book = graph.getHorizonAddressBook(chainId)
  if (!book.entryExists('L2GraphToken')) {
    return null
  }
  return book.getEntry('L2GraphToken')?.address ?? null
}

// -- Task Types --

interface EmptyArgs {
  // No arguments
}

interface BalanceArgs {
  account: string
}

interface TransferArgs {
  to: string
  amount: string
}

interface MintArgs {
  to: string
  amount: string
}

// -- Task Actions --

/**
 * Query GRT balance for an address
 */
const balanceAction: NewTaskActionFunction<BalanceArgs> = async (taskArgs, hre) => {
  if (!taskArgs.account) {
    console.error('\nError: --account is required')
    console.error('Usage: npx hardhat grt:balance --account 0x... --network arbitrumSepolia')
    return
  }
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const conn = await (hre as any).network.connect()
  const networkName = conn.networkName

  const client = createPublicClient({
    transport: custom(conn.provider),
  }) as PublicClient

  const actualChainId = await client.getChainId()
  await graph.autoDetect()
  const forkChainId = graph.getForkTargetChainId()
  const targetChainId = forkChainId ?? actualChainId

  const tokenAddress = getGraphTokenAddress(targetChainId)
  if (!tokenAddress) {
    console.error(`\nError: L2GraphToken not found in address book for chain ${targetChainId}`)
    return
  }

  const account = taskArgs.account as `0x${string}`

  const balance = (await client.readContract({
    address: tokenAddress as `0x${string}`,
    abi: GRAPH_TOKEN_ABI,
    functionName: 'balanceOf',
    args: [account],
  })) as bigint

  console.log(`\nGRT Balance`)
  console.log(`  Account: ${account}`)
  console.log(`  Network: ${networkName} (chainId: ${targetChainId})`)
  console.log(`  Token:   ${tokenAddress}`)
  console.log(`  Balance: ${formatEther(balance)} GRT`)
  console.log()
}

/**
 * Transfer GRT from deployer to an address
 */
const transferAction: NewTaskActionFunction<TransferArgs> = async (taskArgs, hre) => {
  if (!taskArgs.to || !taskArgs.amount) {
    console.error('\nError: --to and --amount are required')
    console.error('Usage: npx hardhat grt:transfer --to 0x... --amount 10000 --network arbitrumSepolia')
    return
  }
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const conn = await (hre as any).network.connect()
  const networkName = conn.networkName

  const client = createPublicClient({
    transport: custom(conn.provider),
  }) as PublicClient

  const actualChainId = await client.getChainId()
  await graph.autoDetect()
  const forkChainId = graph.getForkTargetChainId()
  const targetChainId = forkChainId ?? actualChainId

  const tokenAddress = getGraphTokenAddress(targetChainId)
  if (!tokenAddress) {
    console.error(`\nError: L2GraphToken not found in address book for chain ${targetChainId}`)
    return
  }

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
  const amount = parseEther(taskArgs.amount)

  // Check deployer balance
  const balance = (await client.readContract({
    address: tokenAddress as `0x${string}`,
    abi: GRAPH_TOKEN_ABI,
    functionName: 'balanceOf',
    args: [account.address],
  })) as bigint

  if (balance < amount) {
    console.error(`\nError: Insufficient balance`)
    console.error(`  Deployer balance: ${formatEther(balance)} GRT`)
    console.error(`  Requested:        ${taskArgs.amount} GRT`)
    return
  }

  console.log(`\nTransferring GRT`)
  console.log(`  From:    ${account.address}`)
  console.log(`  To:      ${to}`)
  console.log(`  Amount:  ${taskArgs.amount} GRT`)
  console.log(`  Network: ${networkName} (chainId: ${targetChainId})`)
  console.log(`  Token:   ${tokenAddress}`)

  const walletClient = createWalletClient({
    account,
    transport: custom(conn.provider),
  })

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const hash = await (walletClient as any).writeContract({
    address: tokenAddress as `0x${string}`,
    abi: GRAPH_TOKEN_ABI,
    functionName: 'transfer',
    args: [to, amount],
  })

  console.log(`  TX:      ${hash}`)

  const receipt = await client.waitForTransactionReceipt({ hash })
  if (receipt.status === 'success') {
    const newBalance = (await client.readContract({
      address: tokenAddress as `0x${string}`,
      abi: GRAPH_TOKEN_ABI,
      functionName: 'balanceOf',
      args: [to],
    })) as bigint

    console.log(`\n  Transferred successfully!`)
    console.log(`  Recipient balance: ${formatEther(newBalance)} GRT\n`)
  } else {
    console.error(`\n  Transaction failed\n`)
  }
}

/**
 * Mint GRT to an address (requires deployer to be a minter)
 */
const mintAction: NewTaskActionFunction<MintArgs> = async (taskArgs, hre) => {
  if (!taskArgs.to || !taskArgs.amount) {
    console.error('\nError: --to and --amount are required')
    console.error('Usage: npx hardhat grt:mint --to 0x... --amount 10000 --network arbitrumSepolia')
    return
  }
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const conn = await (hre as any).network.connect()
  const networkName = conn.networkName

  const client = createPublicClient({
    transport: custom(conn.provider),
  }) as PublicClient

  const actualChainId = await client.getChainId()
  await graph.autoDetect()
  const forkChainId = graph.getForkTargetChainId()
  const targetChainId = forkChainId ?? actualChainId

  const tokenAddress = getGraphTokenAddress(targetChainId)
  if (!tokenAddress) {
    console.error(`\nError: L2GraphToken not found in address book for chain ${targetChainId}`)
    return
  }

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
  const amount = parseEther(taskArgs.amount)

  // Check deployer is a minter
  const isMinter = (await client.readContract({
    address: tokenAddress as `0x${string}`,
    abi: GRAPH_TOKEN_ABI,
    functionName: 'isMinter',
    args: [account.address],
  })) as boolean

  if (!isMinter) {
    console.error(`\nError: Deployer ${account.address} is not a minter on GraphToken`)
    console.error('The deployer must be added as a minter by the governor first.')
    return
  }

  console.log(`\nMinting GRT`)
  console.log(`  To:      ${to}`)
  console.log(`  Amount:  ${taskArgs.amount} GRT`)
  console.log(`  Network: ${networkName} (chainId: ${targetChainId})`)
  console.log(`  Token:   ${tokenAddress}`)
  console.log(`  Minter:  ${account.address}`)

  const walletClient = createWalletClient({
    account,
    transport: custom(conn.provider),
  })

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const hash = await (walletClient as any).writeContract({
    address: tokenAddress as `0x${string}`,
    abi: GRAPH_TOKEN_ABI,
    functionName: 'mint',
    args: [to, amount],
  })

  console.log(`  TX:      ${hash}`)

  const receipt = await client.waitForTransactionReceipt({ hash })
  if (receipt.status === 'success') {
    // Read new balance
    const newBalance = (await client.readContract({
      address: tokenAddress as `0x${string}`,
      abi: GRAPH_TOKEN_ABI,
      functionName: 'balanceOf',
      args: [to],
    })) as bigint

    console.log(`\n  Minted successfully!`)
    console.log(`  New balance: ${formatEther(newBalance)} GRT\n`)
  } else {
    console.error(`\n  Transaction failed\n`)
  }
}

/**
 * Show GRT token status: governor, deployer minter check, total supply
 */
const statusAction: NewTaskActionFunction<EmptyArgs> = async (_taskArgs, hre) => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const conn = await (hre as any).network.connect()
  const networkName = conn.networkName

  const client = createPublicClient({
    transport: custom(conn.provider),
  }) as PublicClient

  const actualChainId = await client.getChainId()
  await graph.autoDetect()
  const forkChainId = graph.getForkTargetChainId()
  const targetChainId = forkChainId ?? actualChainId

  const tokenAddress = getGraphTokenAddress(targetChainId)
  if (!tokenAddress) {
    console.error(`\nError: L2GraphToken not found in address book for chain ${targetChainId}`)
    return
  }

  // Read token info in parallel
  const [governor, totalSupply] = await Promise.all([
    client.readContract({
      address: tokenAddress as `0x${string}`,
      abi: GOVERNED_ABI,
      functionName: 'governor',
    }) as Promise<string>,
    client.readContract({
      address: tokenAddress as `0x${string}`,
      abi: GRAPH_TOKEN_ABI,
      functionName: 'totalSupply',
    }) as Promise<bigint>,
  ])

  console.log(`\nGRT Token Status`)
  console.log(`  Token:        ${tokenAddress}`)
  console.log(`  Network:      ${networkName} (chainId: ${targetChainId})`)
  console.log(`  Total supply: ${formatEther(totalSupply)} GRT`)
  console.log(`  Governor:     ${governor}`)

  // Check if governor is a minter
  const governorIsMinter = (await client.readContract({
    address: tokenAddress as `0x${string}`,
    abi: GRAPH_TOKEN_ABI,
    functionName: 'isMinter',
    args: [governor as `0x${string}`],
  })) as boolean
  console.log(`  Governor is minter: ${governorIsMinter ? 'yes' : 'no'}`)

  // Check deployer if key is available
  const keyName = getDeployerKeyName(networkName)
  const deployerKey = await resolveConfigVar(hre, keyName)

  if (deployerKey) {
    const deployer = privateKeyToAccount(deployerKey as `0x${string}`)
    const deployerIsMinter = (await client.readContract({
      address: tokenAddress as `0x${string}`,
      abi: GRAPH_TOKEN_ABI,
      functionName: 'isMinter',
      args: [deployer.address],
    })) as boolean

    console.log(`\n  Deployer:     ${deployer.address}`)
    console.log(`  Deployer is minter: ${deployerIsMinter ? 'yes' : 'no'}`)
    console.log(`  Deployer is governor: ${deployer.address.toLowerCase() === governor.toLowerCase() ? 'yes' : 'no'}`)

    if (!deployerIsMinter) {
      console.log(`\n  To add deployer as minter, the governor must call:`)
      console.log(`    addMinter(${deployer.address})`)
    }
  } else {
    console.log(`\n  Deployer key not configured (${keyName})`)
  }

  console.log()
}

// -- Task Definitions --

/**
 * Show GRT token status: governor, deployer minter status, total supply
 *
 * Examples:
 *   npx hardhat grt:status --network arbitrumSepolia
 */
export const grtStatusTask = task('grt:status', 'Show GRT token status (governor, minter, supply)')
  .setAction(async () => ({ default: statusAction }))
  .build()

/**
 * Query GRT balance for an address
 *
 * Examples:
 *   npx hardhat grt:balance --account 0x1234... --network arbitrumSepolia
 */
export const grtBalanceTask = task('grt:balance', 'Query GRT balance for an address')
  .addOption({
    name: 'account',
    description: 'Address to query balance for',
    type: ArgumentType.STRING,
    defaultValue: '',
  })
  .setAction(async () => ({ default: balanceAction }))
  .build()

/**
 * Transfer testnet GRT from deployer to an address
 *
 * Uses the deployer's existing balance. No minter role needed.
 *
 * Examples:
 *   npx hardhat grt:transfer --to 0x1234... --amount 10000 --network arbitrumSepolia
 */
export const grtTransferTask = task('grt:transfer', 'Transfer GRT from deployer to an address')
  .addOption({
    name: 'to',
    description: 'Recipient address',
    type: ArgumentType.STRING,
    defaultValue: '',
  })
  .addOption({
    name: 'amount',
    description: 'Amount of GRT to transfer (in whole tokens, e.g. 10000)',
    type: ArgumentType.STRING,
    defaultValue: '',
  })
  .setAction(async () => ({ default: transferAction }))
  .build()

/**
 * Mint testnet GRT to an address
 *
 * Requires deployer to be a minter on the GraphToken contract.
 * The deployer/governor is a minter by default after deployment.
 *
 * Examples:
 *   npx hardhat grt:mint --to 0x1234... --amount 10000 --network arbitrumSepolia
 */
export const grtMintTask = task('grt:mint', 'Mint testnet GRT to an address')
  .addOption({
    name: 'to',
    description: 'Recipient address',
    type: ArgumentType.STRING,
    defaultValue: '',
  })
  .addOption({
    name: 'amount',
    description: 'Amount of GRT to mint (in whole tokens, e.g. 10000)',
    type: ArgumentType.STRING,
    defaultValue: '',
  })
  .setAction(async () => ({ default: mintAction }))
  .build()

export default [grtStatusTask, grtBalanceTask, grtTransferTask, grtMintTask]
