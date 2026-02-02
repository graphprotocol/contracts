import { configVariable, task } from 'hardhat/config'
import type { NewTaskActionFunction } from 'hardhat/types/tasks'
import {
  createPublicClient,
  createWalletClient,
  custom,
  encodeFunctionData,
  type PublicClient,
  type WalletClient,
} from 'viem'
import { privateKeyToAccount } from 'viem/accounts'

import { REWARDS_ELIGIBILITY_ORACLE_ABI } from '../lib/abis.js'
import { accountHasRole, enumerateContractRoles, getRoleHash } from '../lib/contract-checks.js'
import { createGovernanceTxBuilder } from '../lib/execute-governance.js'
import { graph } from '../rocketh/deploy.js'

// -- Shared Utilities --

/**
 * Convert network name to env var prefix: arbitrumSepolia → ARBITRUM_SEPOLIA
 */
function networkToEnvPrefix(networkName: string): string {
  return networkName.replace(/([a-z])([A-Z])/g, '$1_$2').toUpperCase()
}

/**
 * Resolve a configuration variable using Hardhat's hook chain (keystore + env fallback)
 */
async function resolveConfigVar(hre: unknown, name: string): Promise<string | undefined> {
  try {
    const variable = configVariable(name)
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const hooks = (hre as any).hooks

    const value = await hooks.runHandlerChain(
      'configurationVariables',
      'fetchValue',
      [variable],
      async (_context: unknown, v: { name: string }) => {
        const envValue = process.env[v.name]
        if (typeof envValue !== 'string') {
          throw new Error(`Variable ${v.name} not found`)
        }
        return envValue
      },
    )
    return value
  } catch {
    return undefined
  }
}

/**
 * Get RewardsEligibilityOracle address from issuance address book
 */
function getREOAddress(chainId: number): string | null {
  const book = graph.getIssuanceAddressBook(chainId)
  if (!book.entryExists('RewardsEligibilityOracle')) {
    return null
  }
  return book.getEntry('RewardsEligibilityOracle')?.address ?? null
}

/**
 * Format duration in seconds to human-readable string
 */
function formatDuration(seconds: bigint): string {
  const days = seconds / 86400n
  const hours = (seconds % 86400n) / 3600n
  const mins = (seconds % 3600n) / 60n

  if (days > 0n) {
    return `${days}d ${hours}h ${mins}m`
  } else if (hours > 0n) {
    return `${hours}h ${mins}m`
  } else {
    return `${mins}m`
  }
}

/**
 * Format timestamp to human-readable string with time ago
 */
function formatTimestamp(timestamp: bigint): string {
  if (timestamp === 0n) {
    return 'never'
  }

  const date = new Date(Number(timestamp) * 1000)
  const now = BigInt(Math.floor(Date.now() / 1000))
  const ago = now - timestamp

  return `${date.toISOString()} (${formatDuration(ago)} ago)`
}

// -- Enable/Disable Shared Logic --

interface SetValidationArgs {
  enabled: boolean
  hre: unknown
}

async function setEligibilityValidation({ enabled, hre }: SetValidationArgs): Promise<void> {
  const action = enabled ? 'Enable' : 'Disable'
  const actionLower = enabled ? 'enable' : 'disable'

  // Connect to network
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const conn = await (hre as any).network.connect()
  const networkName = conn.networkName

  // Create viem client
  const client = createPublicClient({
    transport: custom(conn.provider),
  }) as PublicClient

  const actualChainId = await client.getChainId()
  const forkChainId = graph.getForkTargetChainId()
  const targetChainId = forkChainId ?? actualChainId

  // Get REO address
  const reoAddress = getREOAddress(targetChainId)
  if (!reoAddress) {
    console.error(`\nError: RewardsEligibilityOracle not found in address book for chain ${targetChainId}`)
    return
  }

  // Check current state
  const currentState = (await client.readContract({
    address: reoAddress as `0x${string}`,
    abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
    functionName: 'getEligibilityValidation',
  })) as boolean

  if (currentState === enabled) {
    console.log(`\n✓ Eligibility validation already ${actionLower}d`)
    console.log('  No action needed.\n')
    return
  }

  // Get OPERATOR_ROLE hash
  const operatorRoleHash = await getRoleHash(client, reoAddress, 'OPERATOR_ROLE')
  if (!operatorRoleHash) {
    console.error('\nError: Could not read OPERATOR_ROLE from contract')
    return
  }

  console.log(`\n🔧 ${action} Eligibility Validation`)
  console.log(`   Contract: ${reoAddress}`)
  console.log(`   Network: ${networkName} (chainId: ${targetChainId})`)
  console.log(`   Current: ${currentState ? 'enabled' : 'disabled'}`)
  console.log(`   Target: ${enabled ? 'enabled' : 'disabled'}`)

  // Get deployer account (from keystore or env var)
  const keyName = `${networkToEnvPrefix(networkName === 'fork' ? (process.env.HARDHAT_FORK ?? 'arbitrumSepolia') : networkName)}_DEPLOYER_KEY`
  const deployerKey = await resolveConfigVar(hre, keyName)

  let deployer: string | undefined
  let walletClient: WalletClient | undefined

  if (deployerKey) {
    const account = privateKeyToAccount(deployerKey as `0x${string}`)
    deployer = account.address
    walletClient = createWalletClient({
      account,
      transport: custom(conn.provider),
    })
  }

  // Check if deployer has OPERATOR_ROLE
  const canExecuteDirectly = deployer ? await accountHasRole(client, reoAddress, operatorRoleHash, deployer) : false

  if (canExecuteDirectly && walletClient && deployer) {
    console.log(`\n   Deployer has OPERATOR_ROLE, executing directly...`)

    // Execute directly
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const hash = await (walletClient as any).writeContract({
      address: reoAddress as `0x${string}`,
      abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
      functionName: 'setEligibilityValidation',
      args: [enabled],
    })

    console.log(`   TX: ${hash}`)

    // Wait for confirmation
    const receipt = await client.waitForTransactionReceipt({ hash })
    if (receipt.status === 'success') {
      console.log(`\n✓ Eligibility validation ${actionLower}d successfully\n`)
    } else {
      console.error(`\n✗ Transaction failed\n`)
    }
  } else {
    // Generate governance TX
    console.log(`\n   Requires OPERATOR_ROLE to ${actionLower}`)
    console.log('   Generating governance TX...')

    // Create a minimal environment for the TxBuilder
    const env = {
      name: networkName,
      network: { provider: conn.provider },
      showMessage: console.log,
    }

    const txName = `reo-${actionLower}-validation`
    const builder = await createGovernanceTxBuilder(env as Parameters<typeof createGovernanceTxBuilder>[0], txName, {
      name: `${action} REO Validation`,
      description: `${action} eligibility validation on RewardsEligibilityOracle`,
    })

    // Encode the setEligibilityValidation call
    const data = encodeFunctionData({
      abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
      functionName: 'setEligibilityValidation',
      args: [enabled],
    })

    builder.addTx({
      to: reoAddress,
      data,
      value: '0',
    })

    const txFile = builder.saveToFile()
    console.log(`\n✓ Governance TX saved: ${txFile}`)
    console.log('\nNext steps:')
    console.log('   • Fork testing: npx hardhat deploy:execute-governance --network fork')
    console.log('   • Safe multisig: Upload JSON to Transaction Builder')
    console.log('')
  }
}

// -- Types --

interface TaskArgs {
  // No arguments for these tasks
}

// -- Task Actions --

const enableAction: NewTaskActionFunction<TaskArgs> = async (_taskArgs, hre) => {
  await setEligibilityValidation({ enabled: true, hre })
}

const disableAction: NewTaskActionFunction<TaskArgs> = async (_taskArgs, hre) => {
  await setEligibilityValidation({ enabled: false, hre })
}

const statusAction: NewTaskActionFunction<TaskArgs> = async (_taskArgs, hre) => {
  // Connect to network
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const conn = await (hre as any).network.connect()
  const networkName = conn.networkName

  // Create viem client
  const client = createPublicClient({
    transport: custom(conn.provider),
  }) as PublicClient

  const actualChainId = await client.getChainId()
  const forkChainId = graph.getForkTargetChainId()
  const targetChainId = forkChainId ?? actualChainId

  // Get REO address
  const reoAddress = getREOAddress(targetChainId)
  if (!reoAddress) {
    console.error(`\nError: RewardsEligibilityOracle not found in address book for chain ${targetChainId}`)
    return
  }

  console.log(`\n📊 RewardsEligibilityOracle Status`)
  console.log(`   Address: ${reoAddress}`)
  console.log(`   Network: ${networkName} (chainId: ${targetChainId})`)

  // Read all status values
  const [validationEnabled, eligibilityPeriod, oracleUpdateTimeout, lastOracleUpdateTime] = await Promise.all([
    client.readContract({
      address: reoAddress as `0x${string}`,
      abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
      functionName: 'getEligibilityValidation',
    }) as Promise<boolean>,
    client.readContract({
      address: reoAddress as `0x${string}`,
      abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
      functionName: 'getEligibilityPeriod',
    }) as Promise<bigint>,
    client.readContract({
      address: reoAddress as `0x${string}`,
      abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
      functionName: 'getOracleUpdateTimeout',
    }) as Promise<bigint>,
    client.readContract({
      address: reoAddress as `0x${string}`,
      abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
      functionName: 'getLastOracleUpdateTime',
    }) as Promise<bigint>,
  ])

  // Calculate derived states
  const now = BigInt(Math.floor(Date.now() / 1000))
  const timeSinceLastUpdate = lastOracleUpdateTime > 0n ? now - lastOracleUpdateTime : null
  const timeoutExceeded = timeSinceLastUpdate !== null && timeSinceLastUpdate > oracleUpdateTimeout
  const effectivelyDisabled = !validationEnabled || timeoutExceeded

  // Configuration section
  console.log(`\n🔧 Configuration`)
  console.log(`   Validation enabled: ${validationEnabled ? '✓ yes' : '✗ no'}`)
  console.log(`   Eligibility period: ${formatDuration(eligibilityPeriod)} (${eligibilityPeriod} seconds)`)
  console.log(`   Oracle timeout: ${formatDuration(oracleUpdateTimeout)} (${oracleUpdateTimeout} seconds)`)

  // Oracle activity section
  console.log(`\n📡 Oracle Activity`)
  console.log(`   Last update: ${formatTimestamp(lastOracleUpdateTime)}`)
  if (timeSinceLastUpdate === null) {
    console.log(`   ⚠️  No oracle updates yet`)
  } else if (timeoutExceeded) {
    console.log(`   ⚠️  Timeout exceeded! All indexers treated as eligible (fail-safe active)`)
  }

  // Effective state section
  console.log(`\n🎯 Effective State`)
  if (effectivelyDisabled) {
    console.log(`   Status: ✗ DISABLED (all indexers eligible)`)
    if (!validationEnabled) {
      console.log(`   Reason: Validation toggle is off`)
    } else if (timeoutExceeded) {
      console.log(`   Reason: Oracle timeout exceeded (fail-safe)`)
    }
  } else {
    console.log(`   Status: ✓ ACTIVE (enforcing eligibility)`)
  }

  // Role holders section
  console.log(`\n🔐 Role Holders`)
  const knownRoles = ['GOVERNOR_ROLE', 'PAUSE_ROLE', 'OPERATOR_ROLE', 'ORACLE_ROLE']
  const result = await enumerateContractRoles(client, reoAddress, knownRoles)

  for (const role of result.roles) {
    const memberList = role.members.length > 0 ? role.members.join(', ') : '(none)'
    console.log(`   ${role.name} (${role.memberCount}): ${memberList}`)
  }

  if (result.failedRoles.length > 0) {
    console.log(`   ⚠️  Failed to read: ${result.failedRoles.join(', ')}`)
  }

  console.log()
}

// -- Task Definitions --

/**
 * Enable eligibility validation on RewardsEligibilityOracle
 *
 * Requires OPERATOR_ROLE. If deployer has the role, executes directly.
 * Otherwise generates a governance TX for multisig execution.
 *
 * Examples:
 *   npx hardhat reo:enable --network arbitrumSepolia
 */
export const reoEnableTask = task('reo:enable', 'Enable eligibility validation on RewardsEligibilityOracle')
  .setAction(async () => ({ default: enableAction }))
  .build()

/**
 * Disable eligibility validation on RewardsEligibilityOracle
 *
 * Requires OPERATOR_ROLE. If deployer has the role, executes directly.
 * Otherwise generates a governance TX for multisig execution.
 *
 * WARNING: When validation is disabled, ALL indexers are treated as eligible.
 *
 * Examples:
 *   npx hardhat reo:disable --network arbitrumSepolia
 */
export const reoDisableTask = task('reo:disable', 'Disable eligibility validation on RewardsEligibilityOracle')
  .setAction(async () => ({ default: disableAction }))
  .build()

/**
 * Show detailed status of RewardsEligibilityOracle
 *
 * Displays configuration, oracle activity, effective state, and role holders.
 *
 * Examples:
 *   npx hardhat reo:status --network arbitrumSepolia
 */
export const reoStatusTask = task('reo:status', 'Show detailed RewardsEligibilityOracle status')
  .setAction(async () => ({ default: statusAction }))
  .build()

export default [reoEnableTask, reoDisableTask, reoStatusTask]
