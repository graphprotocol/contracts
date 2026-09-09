import { task } from 'hardhat/config'
import type { NewTaskActionFunction } from 'hardhat/types/tasks'
import { createPublicClient, custom, type PublicClient } from 'viem'

import { PROVIDER_ELIGIBILITY_MANAGEMENT_ABI, REWARDS_ELIGIBILITY_ORACLE_ABI } from '../lib/abis.js'
import { accountHasRole, enumerateContractRoles, getRoleHash } from '../lib/contract-checks.js'
import { executeOrSaveGovernance, resolveDeployer } from '../lib/operator-write.js'
import { formatDuration, formatTimestamp, getDeployerKeyName } from '../lib/task-utils.js'
import { graph } from '../rocketh/deploy.js'

// -- Types --

type REOInstance = 'A' | 'B' | 'Mock'

const VALID_INSTANCES: REOInstance[] = ['A', 'B', 'Mock']

interface TaskArgs {
  instance: string
}

interface RetentionTaskArgs extends TaskArgs {
  seconds: string
}

interface RemoveExpiredTaskArgs extends TaskArgs {
  indexer: string
}

/**
 * Get address book entry name for an REO instance
 */
function reoEntryName(instance: REOInstance): string {
  return `RewardsEligibilityOracle${instance}`
}

/**
 * Get REO address from issuance address book for a specific instance
 */
function getREOAddress(chainId: number, instance: REOInstance): string | null {
  const book = graph.getIssuanceAddressBook(chainId)
  const name = reoEntryName(instance) as Parameters<typeof book.entryExists>[0]
  if (!book.entryExists(name)) {
    return null
  }
  return book.getEntry(name)?.address ?? null
}

/**
 * Parse and validate --instance flag. Returns null if invalid.
 * Accepts case-insensitive input: "a", "A", "b", "B", "mock", "Mock"
 */
function parseInstance(raw: string): REOInstance | null {
  const lower = raw.toLowerCase()
  const mapping: Record<string, REOInstance> = { a: 'A', b: 'B', mock: 'Mock' }
  return mapping[lower] ?? null
}

// -- Enable/Disable Shared Logic --

interface SetValidationArgs {
  enabled: boolean
  instance: REOInstance
  hre: unknown
}

async function setEligibilityValidation({ enabled, instance, hre }: SetValidationArgs): Promise<void> {
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
  await graph.autoDetect()
  const forkChainId = graph.getForkTargetChainId()
  const targetChainId = forkChainId ?? actualChainId

  // Get REO address
  const reoAddress = getREOAddress(targetChainId, instance)
  if (!reoAddress) {
    console.error(`\nError: ${reoEntryName(instance)} not found in address book for chain ${targetChainId}`)
    return
  }

  // Check current state
  const currentState = (await client.readContract({
    address: reoAddress as `0x${string}`,
    abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
    functionName: 'getEligibilityValidation',
  })) as boolean

  if (currentState === enabled) {
    console.log(`\n✓ [${instance}] Eligibility validation already ${actionLower}d`)
    console.log('  No action needed.\n')
    return
  }

  // Get OPERATOR_ROLE hash
  const operatorRoleHash = await getRoleHash(client, reoAddress, 'OPERATOR_ROLE')
  if (!operatorRoleHash) {
    console.error('\nError: Could not read OPERATOR_ROLE from contract')
    return
  }

  console.log(`\n🔧 ${action} Eligibility Validation [Instance ${instance}]`)
  console.log(`   Contract: ${reoAddress}`)
  console.log(`   Network: ${networkName} (chainId: ${targetChainId})`)
  console.log(`   Current: ${currentState ? 'enabled' : 'disabled'}`)
  console.log(`   Target: ${enabled ? 'enabled' : 'disabled'}`)

  const { deployer, walletClient } = await resolveDeployer(hre, { networkName, provider: conn.provider })
  const canExecuteDirectly = deployer ? await accountHasRole(client, reoAddress, operatorRoleHash, deployer) : false

  await executeOrSaveGovernance({
    conn: { networkName, provider: conn.provider },
    publicClient: client,
    walletClient,
    canExecuteDirectly,
    to: reoAddress,
    abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
    functionName: 'setEligibilityValidation',
    args: [enabled],
    roleDescription: 'OPERATOR_ROLE',
    requirementMessage: `OPERATOR_ROLE to ${actionLower}`,
    successMessage: `✓ [${instance}] Eligibility validation ${actionLower}d successfully`,
    txName: `reo-${instance.toLowerCase()}-${actionLower}-validation`,
    governanceName: `${action} REO ${instance} Validation`,
    governanceDescription: `${action} eligibility validation on ${reoEntryName(instance)}`,
  })
}

// -- Status for a single instance --

async function showInstanceStatus(
  client: PublicClient,
  reoAddress: string,
  instance: REOInstance,
  networkName: string,
  targetChainId: number,
): Promise<void> {
  // Mock has a simplified status (no roles, no validation toggle, no oracle)
  if (instance === 'Mock') {
    console.log(`\n📊 RewardsEligibilityOracle Mock Status`)
    console.log(`   Address: ${reoAddress}`)
    console.log(`   Network: ${networkName} (chainId: ${targetChainId})`)
    console.log(`   Type: RewardsEligibilityOracleMock (testnet, indexers self-manage eligibility)`)
    console.log()
    return
  }

  console.log(`\n📊 RewardsEligibilityOracle ${instance} Status`)
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

  // Check if RewardsManager is configured to use this REO instance
  const horizonBook = graph.getHorizonAddressBook(targetChainId)
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const rmAddress = (horizonBook as any).entryExists('RewardsManager')
    ? // eslint-disable-next-line @typescript-eslint/no-explicit-any
      (horizonBook as any).getEntry('RewardsManager')?.address
    : null

  if (rmAddress) {
    try {
      const configuredOracle = (await client.readContract({
        address: rmAddress as `0x${string}`,
        abi: PROVIDER_ELIGIBILITY_MANAGEMENT_ABI,
        functionName: 'getProviderEligibilityOracle',
      })) as string

      const isConfigured = configuredOracle.toLowerCase() === reoAddress.toLowerCase()
      if (isConfigured) {
        console.log(`   RewardsManager: ✓ using this instance`)
      } else if (configuredOracle === '0x0000000000000000000000000000000000000000') {
        console.log(`   RewardsManager: ✗ no oracle configured`)
      } else {
        console.log(`   RewardsManager: ✗ using different oracle (${configuredOracle})`)
      }
    } catch {
      console.log(`   RewardsManager: ? not upgraded yet (getProviderEligibilityOracle not available)`)
    }
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

// -- Indexer listing for a single instance --

async function showInstanceIndexers(
  client: PublicClient,
  reoAddress: string,
  instance: REOInstance,
  networkName: string,
  targetChainId: number,
): Promise<void> {
  console.log(`\n📋 RewardsEligibilityOracle ${instance} — Tracked Indexers`)
  console.log(`   Address: ${reoAddress}`)
  console.log(`   Network: ${networkName} (chainId: ${targetChainId})`)

  // Get indexer count and eligibility period in parallel
  const [indexerCount, eligibilityPeriod, validationEnabled] = await Promise.all([
    client.readContract({
      address: reoAddress as `0x${string}`,
      abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
      functionName: 'getIndexerCount',
    }) as Promise<bigint>,
    client.readContract({
      address: reoAddress as `0x${string}`,
      abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
      functionName: 'getEligibilityPeriod',
    }) as Promise<bigint>,
    client.readContract({
      address: reoAddress as `0x${string}`,
      abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
      functionName: 'getEligibilityValidation',
    }) as Promise<boolean>,
  ])

  console.log(`   Validation: ${validationEnabled ? 'enabled' : 'disabled'}`)
  console.log(`   Eligibility period: ${formatDuration(eligibilityPeriod)}`)
  console.log(`   Tracked indexers: ${indexerCount}`)

  if (indexerCount === 0n) {
    console.log('\n   No indexers tracked.\n')
    return
  }

  // Fetch all indexer addresses
  const indexers = (await client.readContract({
    address: reoAddress as `0x${string}`,
    abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
    functionName: 'getIndexers',
  })) as `0x${string}`[]

  // Batch-read eligibility and renewal time for each indexer
  const details = await Promise.all(
    indexers.map(async (indexer) => {
      const [eligible, renewalTime] = await Promise.all([
        client.readContract({
          address: reoAddress as `0x${string}`,
          abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
          functionName: 'isEligible',
          args: [indexer],
        }) as Promise<boolean>,
        client.readContract({
          address: reoAddress as `0x${string}`,
          abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
          functionName: 'getEligibilityRenewalTime',
          args: [indexer],
        }) as Promise<bigint>,
      ])
      return { indexer, eligible, renewalTime }
    }),
  )

  // Sort by renewal time (most recent first), then by address within each group
  details.sort((a, b) => {
    if (a.renewalTime !== b.renewalTime) {
      return a.renewalTime < b.renewalTime ? 1 : -1
    }
    return a.indexer.toLowerCase() < b.indexer.toLowerCase() ? -1 : 1
  })

  // Display results grouped by renewal time with blank lines between groups
  let lastRenewalTime: bigint | null = null
  for (const { indexer, eligible, renewalTime } of details) {
    if (lastRenewalTime !== null && renewalTime !== lastRenewalTime) {
      console.log('')
    }
    lastRenewalTime = renewalTime
    const status = eligible ? '✓' : '✗'
    console.log(`   ${status} ${indexer}  renewed ${formatTimestamp(renewalTime)}`)
  }

  // Summary
  const eligibleCount = details.filter((d) => d.eligible).length
  console.log(`\n   Summary: ${eligibleCount}/${details.length} eligible\n`)
}

// -- Retention Period Shared Logic --

const retentionAction: NewTaskActionFunction<RetentionTaskArgs> = async (taskArgs, hre) => {
  const instance = parseInstance(taskArgs.instance)
  if (!instance) {
    console.error(`\nError: --instance is required (a, b, or mock)`)
    return
  }
  if (instance === 'Mock') {
    console.error(`\nError: Mock REO has no retention period`)
    return
  }

  const raw = (taskArgs.seconds ?? '').trim()
  const isSet = raw !== ''
  if (isSet && !/^\d+$/.test(raw)) {
    console.error(`\nError: --seconds must be a non-negative integer (got "${taskArgs.seconds}")`)
    return
  }
  const newPeriod = isSet ? BigInt(raw) : null

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

  const reoAddress = getREOAddress(targetChainId, instance)
  if (!reoAddress) {
    console.error(`\nError: ${reoEntryName(instance)} not found in address book for chain ${targetChainId}`)
    return
  }

  const currentPeriod = (await client.readContract({
    address: reoAddress as `0x${string}`,
    abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
    functionName: 'getIndexerRetentionPeriod',
  })) as bigint

  if (newPeriod === null) {
    console.log(`\n📐 Indexer Retention Period [Instance ${instance}]`)
    console.log(`   Contract: ${reoAddress}`)
    console.log(`   Network: ${networkName} (chainId: ${targetChainId})`)
    console.log(`   Current: ${formatDuration(currentPeriod)} (${currentPeriod}s)\n`)
    return
  }

  if (currentPeriod === newPeriod) {
    console.log(`\n✓ [${instance}] Retention period already ${formatDuration(newPeriod)} (${newPeriod}s)`)
    console.log('  No action needed.\n')
    return
  }

  const operatorRoleHash = await getRoleHash(client, reoAddress, 'OPERATOR_ROLE')
  if (!operatorRoleHash) {
    console.error('\nError: Could not read OPERATOR_ROLE from contract')
    return
  }

  console.log(`\n🔧 Set Indexer Retention Period [Instance ${instance}]`)
  console.log(`   Contract: ${reoAddress}`)
  console.log(`   Network: ${networkName} (chainId: ${targetChainId})`)
  console.log(`   Current: ${formatDuration(currentPeriod)} (${currentPeriod}s)`)
  console.log(`   Target:  ${formatDuration(newPeriod)} (${newPeriod}s)`)

  const { deployer, walletClient } = await resolveDeployer(hre, { networkName, provider: conn.provider })
  const canExecuteDirectly = deployer ? await accountHasRole(client, reoAddress, operatorRoleHash, deployer) : false

  await executeOrSaveGovernance({
    conn: { networkName, provider: conn.provider },
    publicClient: client,
    walletClient,
    canExecuteDirectly,
    to: reoAddress,
    abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
    functionName: 'setIndexerRetentionPeriod',
    args: [newPeriod],
    roleDescription: 'OPERATOR_ROLE',
    requirementMessage: 'OPERATOR_ROLE',
    successMessage: `✓ [${instance}] Retention period set to ${formatDuration(newPeriod)}`,
    txName: `reo-${instance.toLowerCase()}-retention`,
    governanceName: `Set REO ${instance} Retention Period`,
    governanceDescription: `Set indexerRetentionPeriod to ${newPeriod}s on ${reoEntryName(instance)}`,
  })
}

// -- Remove Expired Indexer Shared Logic --

const removeExpiredAction: NewTaskActionFunction<RemoveExpiredTaskArgs> = async (taskArgs, hre) => {
  const instance = parseInstance(taskArgs.instance)
  if (!instance) {
    console.error(`\nError: --instance is required (a, b, or mock)`)
    return
  }
  if (instance === 'Mock') {
    console.error(`\nError: Mock REO has no expired-indexer tracking`)
    return
  }

  const indexer = (taskArgs.indexer ?? '').trim()
  if (!/^0x[0-9a-fA-F]{40}$/.test(indexer)) {
    console.error(`\nError: --indexer must be a 20-byte hex address (got "${taskArgs.indexer}")`)
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

  const reoAddress = getREOAddress(targetChainId, instance)
  if (!reoAddress) {
    console.error(`\nError: ${reoEntryName(instance)} not found in address book for chain ${targetChainId}`)
    return
  }

  // Pre-flight reads so we fail with a readable message rather than a silent contract revert.
  const [retentionPeriod, renewalTime] = await Promise.all([
    client.readContract({
      address: reoAddress as `0x${string}`,
      abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
      functionName: 'getIndexerRetentionPeriod',
    }) as Promise<bigint>,
    client.readContract({
      address: reoAddress as `0x${string}`,
      abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
      functionName: 'getEligibilityRenewalTime',
      args: [indexer as `0x${string}`],
    }) as Promise<bigint>,
  ])

  console.log(`\n🧹 Remove Expired Indexer [Instance ${instance}]`)
  console.log(`   Contract: ${reoAddress}`)
  console.log(`   Network: ${networkName} (chainId: ${targetChainId})`)
  console.log(`   Indexer: ${indexer}`)
  console.log(`   Renewal time: ${formatTimestamp(renewalTime)} (${renewalTime})`)
  console.log(`   Retention period: ${formatDuration(retentionPeriod)} (${retentionPeriod}s)`)

  if (renewalTime === 0n) {
    // Either never tracked, or already removed (storage cleared on remove).
    console.log(`\n   Indexer is not currently tracked. Nothing to remove.\n`)
    return
  }

  const expiresAt = renewalTime + retentionPeriod
  const now = BigInt(Math.floor(Date.now() / 1000))
  if (now < expiresAt) {
    const wait = expiresAt - now
    console.error(`\n✗ Not yet removable: needs ${formatDuration(wait)} (${wait}s) more.`)
    console.error(`  Expires at ${formatTimestamp(expiresAt)}.`)
    console.error(`  Lower the retention period (reo:retention --seconds <R>) or wait.\n`)
    return
  }

  const { deployer, walletClient } = await resolveDeployer(hre, { networkName, provider: conn.provider })
  if (!deployer || !walletClient) {
    const keyName = getDeployerKeyName(networkName)
    console.error(`\nError: ${keyName} not configured.`)
    console.error(`  Set it with: npx hardhat keystore set ${keyName}\n`)
    return
  }

  console.log(`\n   Sender: ${deployer} (permissionless call, paying gas)`)

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const hash = await (walletClient as any).writeContract({
    address: reoAddress as `0x${string}`,
    abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
    functionName: 'removeExpiredIndexer',
    args: [indexer as `0x${string}`],
  })
  console.log(`   TX: ${hash}`)

  const receipt = await client.waitForTransactionReceipt({ hash })
  if (receipt.status === 'success') {
    console.log(`\n✓ [${instance}] Indexer ${indexer} removed (or already absent)\n`)
  } else {
    console.error(`\n✗ Transaction failed\n`)
  }
}

// -- Task Actions --

const enableAction: NewTaskActionFunction<TaskArgs> = async (taskArgs, hre) => {
  const instance = parseInstance(taskArgs.instance)
  if (!instance) {
    console.error(`\nError: --instance is required (a, b, or mock)`)
    return
  }
  if (instance === 'Mock') {
    console.error(`\nError: Mock REO has no validation toggle — it's always active`)
    return
  }
  await setEligibilityValidation({ enabled: true, instance, hre })
}

const disableAction: NewTaskActionFunction<TaskArgs> = async (taskArgs, hre) => {
  const instance = parseInstance(taskArgs.instance)
  if (!instance) {
    console.error(`\nError: --instance is required (a, b, or mock)`)
    return
  }
  if (instance === 'Mock') {
    console.error(`\nError: Mock REO has no validation toggle — it's always active`)
    return
  }
  await setEligibilityValidation({ enabled: false, instance, hre })
}

const indexersAction: NewTaskActionFunction<TaskArgs> = async (taskArgs, hre) => {
  // Connect to network
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const conn = await (hre as any).network.connect()
  const networkName = conn.networkName

  // Create viem client
  const client = createPublicClient({
    transport: custom(conn.provider),
  }) as PublicClient

  const actualChainId = await client.getChainId()
  await graph.autoDetect()
  const forkChainId = graph.getForkTargetChainId()
  const targetChainId = forkChainId ?? actualChainId

  // Determine which instances to show
  const requestedInstance = taskArgs.instance ? parseInstance(taskArgs.instance) : null
  const instancesToShow: REOInstance[] = requestedInstance ? [requestedInstance] : VALID_INSTANCES

  let found = false
  for (const instance of instancesToShow) {
    const reoAddress = getREOAddress(targetChainId, instance)
    if (reoAddress) {
      found = true
      await showInstanceIndexers(client, reoAddress, instance, networkName, targetChainId)
    } else if (requestedInstance) {
      console.error(`\nError: ${reoEntryName(instance)} not found in address book for chain ${targetChainId}`)
    }
  }

  if (!found) {
    console.error(`\nError: No REO instances found in address book for chain ${targetChainId}`)
  }
}

const statusAction: NewTaskActionFunction<TaskArgs> = async (taskArgs, hre) => {
  // Connect to network
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const conn = await (hre as any).network.connect()
  const networkName = conn.networkName

  // Create viem client
  const client = createPublicClient({
    transport: custom(conn.provider),
  }) as PublicClient

  const actualChainId = await client.getChainId()
  await graph.autoDetect()
  const forkChainId = graph.getForkTargetChainId()
  const targetChainId = forkChainId ?? actualChainId

  // Determine which instances to show
  const requestedInstance = taskArgs.instance ? parseInstance(taskArgs.instance) : null
  const instancesToShow: REOInstance[] = requestedInstance ? [requestedInstance] : VALID_INSTANCES

  let found = false
  for (const instance of instancesToShow) {
    const reoAddress = getREOAddress(targetChainId, instance)
    if (reoAddress) {
      found = true
      await showInstanceStatus(client, reoAddress, instance, networkName, targetChainId)
    } else if (requestedInstance) {
      // Only error if a specific instance was requested and not found
      console.error(`\nError: ${reoEntryName(instance)} not found in address book for chain ${targetChainId}`)
    }
  }

  if (!found) {
    console.error(`\nError: No REO instances found in address book for chain ${targetChainId}`)
  }
}

// -- Task Definitions --

/**
 * Enable eligibility validation on a REO instance
 *
 * Requires OPERATOR_ROLE. If deployer has the role, executes directly.
 * Otherwise generates a governance TX for multisig execution.
 *
 * Examples:
 *   npx hardhat reo:enable --instance a --network arbitrumSepolia
 */
export const reoEnableTask = task('reo:enable', 'Enable eligibility validation on a REO instance')
  .addOption({
    name: 'instance',
    description: 'REO instance (a, b, or mock)',
    defaultValue: '',
  })
  .setAction(async () => ({ default: enableAction }))
  .build()

/**
 * Disable eligibility validation on a REO instance
 *
 * Requires OPERATOR_ROLE. If deployer has the role, executes directly.
 * Otherwise generates a governance TX for multisig execution.
 *
 * WARNING: When validation is disabled, ALL indexers are treated as eligible.
 *
 * Examples:
 *   npx hardhat reo:disable --instance b --network arbitrumSepolia
 */
export const reoDisableTask = task('reo:disable', 'Disable eligibility validation on a REO instance')
  .addOption({
    name: 'instance',
    description: 'REO instance (a, b, or mock)',
    defaultValue: '',
  })
  .setAction(async () => ({ default: disableAction }))
  .build()

/**
 * Show detailed status of REO instance(s)
 *
 * Displays configuration, oracle activity, effective state, and role holders.
 * If --instance is omitted, shows status for all deployed instances.
 *
 * Examples:
 *   npx hardhat reo:status --network arbitrumSepolia              # show all
 *   npx hardhat reo:status --instance a --network arbitrumSepolia # show A only
 */
export const reoStatusTask = task('reo:status', 'Show detailed REO status')
  .addOption({
    name: 'instance',
    description: 'REO instance (a, b, or mock; omit for all)',
    defaultValue: '',
  })
  .setAction(async () => ({ default: statusAction }))
  .build()

/**
 * List tracked indexers with eligibility info
 *
 * Shows each indexer's eligibility status, renewal time, and expiry.
 * If --instance is omitted, shows indexers for all deployed instances.
 *
 * Examples:
 *   npx hardhat reo:indexers --network arbitrumSepolia              # show all
 *   npx hardhat reo:indexers --instance a --network arbitrumSepolia # show A only
 */
export const reoIndexersTask = task('reo:indexers', 'List tracked indexers with eligibility info')
  .addOption({
    name: 'instance',
    description: 'REO instance (a, b, or mock; omit for all)',
    defaultValue: '',
  })
  .setAction(async () => ({ default: indexersAction }))
  .build()

/**
 * Get or set indexerRetentionPeriod on a REO instance
 *
 * Without `--seconds`: reads and prints the current period (no transaction).
 * With `--seconds <R>`: calls `setIndexerRetentionPeriod(R)`. Requires
 * OPERATOR_ROLE; if the deployer has it, executes directly, otherwise
 * generates a governance TX for multisig execution.
 *
 * Shrinking this period lets `removeExpiredIndexer` permissionlessly clean up
 * stale entries; restore to the canonical value (typically 31_536_000 = 365d)
 * immediately after.
 *
 * Examples:
 *   npx hardhat reo:retention --instance a --network arbitrumOne                       # read
 *   npx hardhat reo:retention --instance a --seconds 31536000 --network arbitrumOne   # set
 */
export const reoRetentionTask = task('reo:retention', 'Get or set indexerRetentionPeriod on a REO instance')
  .addOption({
    name: 'instance',
    description: 'REO instance (a, b, or mock)',
    defaultValue: '',
  })
  .addOption({
    name: 'seconds',
    description: 'New retention period in seconds; omit to read (e.g., 31536000 = 365d)',
    defaultValue: '',
  })
  .setAction(async () => ({ default: retentionAction }))
  .build()

/**
 * Permissionlessly remove a tracked indexer once `renewalTime + retentionPeriod`
 * has passed. Deployer key is used only for gas — no role required by the contract.
 *
 * Pre-flight checks the renewal time and retention period; bails with a readable
 * message if the indexer isn't tracked or isn't yet expired.
 *
 * Examples:
 *   npx hardhat reo:remove-expired --instance a --indexer 0x86868BB556DeDcd0768854A5aF9e62f2e9129D46 --network arbitrumOne
 */
export const reoRemoveExpiredTask = task(
  'reo:remove-expired',
  'Permissionlessly remove a tracked indexer past retention',
)
  .addOption({
    name: 'instance',
    description: 'REO instance (a, b, or mock)',
    defaultValue: '',
  })
  .addOption({
    name: 'indexer',
    description: 'Indexer address to remove',
    defaultValue: '',
  })
  .setAction(async () => ({ default: removeExpiredAction }))
  .build()

export default [reoEnableTask, reoDisableTask, reoStatusTask, reoIndexersTask, reoRetentionTask, reoRemoveExpiredTask]
