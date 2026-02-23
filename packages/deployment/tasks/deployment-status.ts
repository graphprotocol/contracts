import { task } from 'hardhat/config'
import { ArgumentType } from 'hardhat/types/arguments'
import type { NewTaskActionFunction } from 'hardhat/types/tasks'
import { createPublicClient, custom, http, type PublicClient } from 'viem'

import {
  IISSUANCE_TARGET_INTERFACE_ID,
  IREWARDS_MANAGER_INTERFACE_ID,
  ISSUANCE_ALLOCATOR_ABI,
  REWARDS_ELIGIBILITY_ORACLE_ABI,
  REWARDS_MANAGER_ABI,
} from '../lib/abis.js'
import type { AddressBookOps } from '../lib/address-book-ops.js'
import {
  checkIssuanceAllocatorActivation,
  checkOperatorRole,
  getReclaimAddress,
  RECLAIM_CONTRACT_NAMES,
  RECLAIM_REASONS,
  type ReclaimReasonKey,
  supportsInterface,
} from '../lib/contract-checks.js'
import { type AddressBookType, getContractsByAddressBook } from '../lib/contract-registry.js'
import { getContractStatusLine } from '../lib/sync-utils.js'
import { graph } from '../rocketh/deploy.js'

/** Get deployable contract names for an address book (requires explicit deployable: true) */
function getDeployableContracts(addressBook: AddressBookType): string[] {
  return getContractsByAddressBook(addressBook)
    .filter(([_, meta]) => meta.deployable === true)
    .map(([name]) => name)
}

/** Integration check result */
interface IntegrationCheck {
  ok: boolean | null // null = not applicable / not deployed
  label: string
}

interface TaskArgs {
  package: string
}

const action: NewTaskActionFunction<TaskArgs> = async (taskArgs, hre) => {
  // HH v3: Connect to network to get chainId and network name
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const conn = await (hre as any).network.connect()
  const networkName = conn.networkName
  const packageFilter = taskArgs.package.toLowerCase()

  // Get configured chain ID from network config (always available)
  const configuredChainId = conn.networkConfig?.chainId as number | undefined

  // Default RPC URLs for read-only access (no accounts needed)
  const DEFAULT_RPC_URLS: Record<string, string> = {
    arbitrumOne: 'https://arb1.arbitrum.io/rpc',
    arbitrumSepolia: 'https://sepolia-rollup.arbitrum.io/rpc',
  }

  // Get RPC URL: prefer env var, then default
  const envRpcUrl =
    networkName === 'arbitrumSepolia'
      ? process.env.ARBITRUM_SEPOLIA_RPC
      : networkName === 'arbitrumOne'
        ? process.env.ARBITRUM_ONE_RPC
        : undefined
  const rpcUrl = envRpcUrl || DEFAULT_RPC_URLS[networkName]

  // Get viem public client for on-chain checks
  // Use direct HTTP transport to RPC URL (bypasses Hardhat's account resolution)
  let client: PublicClient | undefined
  let actualChainId: number | undefined
  let providerError: string | undefined

  if (rpcUrl) {
    // Create read-only client directly to RPC (no accounts needed)
    try {
      client = createPublicClient({
        transport: http(rpcUrl),
      }) as PublicClient
      actualChainId = await client.getChainId()
    } catch (e) {
      client = undefined
      const errMsg = e instanceof Error ? e.message : String(e)
      providerError = errMsg.split('\n')[0]
    }
  } else {
    // No RPC URL available - try Hardhat's provider (may fail if accounts not configured)
    try {
      if (conn.provider) {
        client = createPublicClient({
          transport: custom(conn.provider),
        }) as PublicClient
        actualChainId = await client.getChainId()
      }
    } catch (e) {
      // Provider failed - disable on-chain checks
      client = undefined

      // Extract error message (may be nested in viem error or cause chain)
      let errMsg = e instanceof Error ? e.message : String(e)
      const cause = e instanceof Error ? (e as Error & { cause?: Error }).cause : undefined
      if (cause?.message) {
        errMsg = cause.message
      }

      providerError = errMsg.split('\n')[0]
    }
  }

  // Determine target chain ID: use fork target, then configured, then actual, then fallback
  const forkChainId = graph.getForkTargetChainId()
  const isForkMode = forkChainId !== null
  const targetChainId = forkChainId ?? configuredChainId ?? actualChainId ?? 31337

  // Show status header with chain info
  if (isForkMode) {
    console.log(`\n🔍 Status: ${networkName} (fork of chainId ${targetChainId})\n`)
  } else if (actualChainId && actualChainId !== targetChainId) {
    console.log(`\n🔍 Status: ${networkName} (chainId: ${actualChainId})`)
    console.log(`⚠️  Warning: Connected chain (${actualChainId}) differs from target (${targetChainId})`)
    console.log(`   Address book lookups use chainId ${targetChainId}\n`)
  } else {
    console.log(`\n🔍 Status: ${networkName} (chainId: ${targetChainId})\n`)
  }

  // Show provider warning if we couldn't connect (but continue with address book lookups)
  if (providerError) {
    console.log(`⚠️  Provider unavailable: ${providerError}`)
    console.log(`   On-chain checks disabled. Set the missing variable or use --network hardhat for local testing.\n`)
  }

  // Get address books
  const horizonAddressBook = graph.getHorizonAddressBook(targetChainId)
  const subgraphServiceAddressBook = graph.getSubgraphServiceAddressBook(targetChainId)
  const issuanceAddressBook = graph.getIssuanceAddressBook(targetChainId)

  // Horizon contracts (deploy targets only)
  if (packageFilter === 'all' || packageFilter === 'horizon') {
    console.log('📦 Horizon')
    for (const name of getDeployableContracts('horizon')) {
      const result = await getContractStatusLine(client, 'horizon', horizonAddressBook, name)
      console.log(`  ${result.line}`)
      printWarnings(result.warnings)

      // Integration checks for RewardsManager (only if deployed)
      if (name === 'RewardsManager' && client && result.exists) {
        const checks = await getRewardsManagerChecks(client, horizonAddressBook)
        for (const check of checks) {
          printCheck(check)
        }
      }
    }
  }

  // SubgraphService contracts
  if (packageFilter === 'all' || packageFilter === 'subgraph-service') {
    console.log('\n📦 SubgraphService')
    for (const name of getDeployableContracts('subgraph-service')) {
      const result = await getContractStatusLine(client, 'subgraph-service', subgraphServiceAddressBook, name)
      console.log(`  ${result.line}`)
      printWarnings(result.warnings)
    }
  }

  // Issuance contracts
  if (packageFilter === 'all' || packageFilter === 'issuance') {
    console.log('\n📦 Issuance')
    for (const name of getDeployableContracts('issuance')) {
      const result = await getContractStatusLine(client, 'issuance', issuanceAddressBook, name)
      console.log(`  ${result.line}`)
      printWarnings(result.warnings)

      // Integration checks for IssuanceAllocator (only if deployed)
      if (name === 'IssuanceAllocator' && client && result.exists) {
        const checks = await getIssuanceAllocatorChecks(client, horizonAddressBook, issuanceAddressBook)
        for (const check of checks) {
          printCheck(check)
        }
      }

      // Integration checks for RewardsEligibilityOracle (only if deployed)
      if (name === 'RewardsEligibilityOracle' && client && result.exists) {
        const checks = await getRewardsEligibilityOracleChecks(client, horizonAddressBook, issuanceAddressBook)
        for (const check of checks) {
          printCheck(check)
        }
      }

      // Integration checks for reclaim addresses (only if deployed)
      if (name.startsWith('ReclaimedRewardsFor') && client && result.exists) {
        const checks = await getReclaimAddressChecks(client, horizonAddressBook, issuanceAddressBook, name)
        for (const check of checks) {
          printCheck(check)
        }
      }
    }
  }

  console.log()
}

function printCheck(check: IntegrationCheck): void {
  const icon = check.ok === null ? '○' : check.ok ? '✓' : '✗'
  console.log(`        ${icon} ${check.label}`)
}

function printWarnings(warnings: string[] | undefined): void {
  if (!warnings) return
  for (const warning of warnings) {
    console.log(`      ⚠ ${warning}`)
  }
}

async function getRewardsManagerChecks(client: PublicClient, horizonBook: AddressBookOps): Promise<IntegrationCheck[]> {
  const checks: IntegrationCheck[] = []
  const rmAddress = horizonBook.entryExists('RewardsManager') ? horizonBook.getEntry('RewardsManager')?.address : null

  if (!rmAddress) return checks

  // Check IRewardsManager support (latest interface version)
  const supportsRewardsManager = await supportsInterface(client, rmAddress, IREWARDS_MANAGER_INTERFACE_ID)
  checks.push({ ok: supportsRewardsManager, label: `implements IRewardsManager (${IREWARDS_MANAGER_INTERFACE_ID})` })

  // Check IIssuanceTarget support (required for issuance integration)
  const supportsIssuanceTarget = await supportsInterface(client, rmAddress, IISSUANCE_TARGET_INTERFACE_ID)
  checks.push({ ok: supportsIssuanceTarget, label: `implements IIssuanceTarget (${IISSUANCE_TARGET_INTERFACE_ID})` })

  return checks
}

async function getIssuanceAllocatorChecks(
  client: PublicClient,
  horizonBook: AddressBookOps,
  issuanceBook: AddressBookOps,
): Promise<IntegrationCheck[]> {
  const checks: IntegrationCheck[] = []

  const iaAddress = issuanceBook.entryExists('IssuanceAllocator')
    ? issuanceBook.getEntry('IssuanceAllocator')?.address
    : null
  const rmAddress = horizonBook.entryExists('RewardsManager') ? horizonBook.getEntry('RewardsManager')?.address : null
  const gtAddress = horizonBook.entryExists('L2GraphToken') ? horizonBook.getEntry('L2GraphToken')?.address : null

  if (!iaAddress || !rmAddress || !gtAddress) return checks

  // RM must implement IIssuanceTarget for IA integration
  const rmSupportsTarget = await supportsInterface(client, rmAddress, IISSUANCE_TARGET_INTERFACE_ID)
  checks.push({ ok: rmSupportsTarget, label: `RM implements IIssuanceTarget (${IISSUANCE_TARGET_INTERFACE_ID})` })

  // Only check activation if RM supports IIssuanceTarget (has been upgraded)
  if (rmSupportsTarget) {
    const activation = await checkIssuanceAllocatorActivation(client, iaAddress, rmAddress, gtAddress)
    checks.push({ ok: activation.iaIntegrated, label: 'RM.issuanceAllocator == this' })
    checks.push({ ok: activation.iaMinter, label: 'GraphToken.MINTER_ROLE granted' })
  } else {
    // RM not upgraded yet - can't check activation
    checks.push({ ok: null, label: 'RM.issuanceAllocator == this (RM not upgraded)' })
    checks.push({ ok: null, label: 'GraphToken.MINTER_ROLE granted (RM not upgraded)' })
  }

  // Check default target configured
  try {
    const defaultTarget = (await client.readContract({
      address: iaAddress as `0x${string}`,
      abi: ISSUANCE_ALLOCATOR_ABI,
      functionName: 'getDefaultTarget',
    })) as string
    const hasDefaultTarget = defaultTarget !== '0x0000000000000000000000000000000000000000'
    checks.push({ ok: hasDefaultTarget, label: 'defaultTarget configured' })
  } catch {
    // Function not available
  }

  return checks
}

async function getRewardsEligibilityOracleChecks(
  client: PublicClient,
  horizonBook: AddressBookOps,
  issuanceBook: AddressBookOps,
): Promise<IntegrationCheck[]> {
  const checks: IntegrationCheck[] = []

  const reoAddress = issuanceBook.entryExists('RewardsEligibilityOracle')
    ? issuanceBook.getEntry('RewardsEligibilityOracle')?.address
    : null
  const rmAddress = horizonBook.entryExists('RewardsManager') ? horizonBook.getEntry('RewardsManager')?.address : null
  const controllerAddress = horizonBook.entryExists('Controller') ? horizonBook.getEntry('Controller')?.address : null

  if (!reoAddress || !rmAddress) return checks

  // Get governor and pause guardian from Controller for role checks
  let governor: string | null = null
  let pauseGuardian: string | null = null
  if (controllerAddress) {
    try {
      governor = (await client.readContract({
        address: controllerAddress as `0x${string}`,
        abi: [
          {
            inputs: [],
            name: 'getGovernor',
            outputs: [{ type: 'address' }],
            stateMutability: 'view',
            type: 'function',
          },
        ],
        functionName: 'getGovernor',
      })) as string
    } catch {
      // Controller doesn't have getGovernor
    }
    try {
      pauseGuardian = (await client.readContract({
        address: controllerAddress as `0x${string}`,
        abi: [
          {
            inputs: [],
            name: 'pauseGuardian',
            outputs: [{ type: 'address' }],
            stateMutability: 'view',
            type: 'function',
          },
        ],
        functionName: 'pauseGuardian',
      })) as string
    } catch {
      // Controller doesn't have pauseGuardian
    }
  }

  // Check access control roles
  try {
    const governorRole = (await client.readContract({
      address: reoAddress as `0x${string}`,
      abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
      functionName: 'GOVERNOR_ROLE',
    })) as `0x${string}`

    if (governor) {
      const governorHasRole = (await client.readContract({
        address: reoAddress as `0x${string}`,
        abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
        functionName: 'hasRole',
        args: [governorRole, governor as `0x${string}`],
      })) as boolean
      checks.push({ ok: governorHasRole, label: 'governor has GOVERNOR_ROLE' })
    }
  } catch {
    // Role check not available
  }

  // Check PAUSE_ROLE
  try {
    const pauseRole = (await client.readContract({
      address: reoAddress as `0x${string}`,
      abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
      functionName: 'PAUSE_ROLE',
    })) as `0x${string}`

    if (pauseGuardian) {
      const pauseGuardianHasRole = (await client.readContract({
        address: reoAddress as `0x${string}`,
        abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
        functionName: 'hasRole',
        args: [pauseRole, pauseGuardian as `0x${string}`],
      })) as boolean
      checks.push({ ok: pauseGuardianHasRole, label: 'pause guardian has PAUSE_ROLE' })
    }
  } catch {
    // Role check not available
  }

  // Check OPERATOR_ROLE using shared function (single source of truth)
  const networkOperator = issuanceBook.entryExists('NetworkOperator')
    ? (issuanceBook.getEntry('NetworkOperator')?.address ?? null)
    : null

  try {
    const operatorCheck = await checkOperatorRole(client, reoAddress, networkOperator)
    // For status check: NetworkOperator not configured is always a configuration failure
    // (even if role assignment is technically correct with 0 holders)
    const statusOk = networkOperator === null ? false : operatorCheck.ok
    checks.push({ ok: statusOk, label: operatorCheck.message })
  } catch {
    checks.push({ ok: null, label: 'OPERATOR_ROLE (check failed)' })
  }

  // Check if configured in RM
  try {
    const currentREO = (await client.readContract({
      address: rmAddress as `0x${string}`,
      abi: REWARDS_MANAGER_ABI,
      functionName: 'getRewardsEligibilityOracle',
    })) as string
    const configured = currentREO.toLowerCase() === reoAddress.toLowerCase()
    checks.push({ ok: configured, label: 'RM.rewardsEligibilityOracle == this' })
  } catch {
    // Function not available on old RM
  }

  // Check if validation is enabled
  try {
    const enabled = (await client.readContract({
      address: reoAddress as `0x${string}`,
      abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
      functionName: 'getEligibilityValidation',
    })) as boolean
    checks.push({ ok: enabled, label: 'eligibility validation enabled' })
  } catch {
    // Function not available
  }

  // Check last oracle update time (indicates if active)
  try {
    const lastUpdate = (await client.readContract({
      address: reoAddress as `0x${string}`,
      abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
      functionName: 'getLastOracleUpdateTime',
    })) as bigint
    const hasUpdates = lastUpdate > 0n
    checks.push({ ok: hasUpdates, label: 'oracle has processed updates' })
  } catch {
    // Function not available
  }

  return checks
}

async function getReclaimAddressChecks(
  client: PublicClient,
  horizonBook: AddressBookOps,
  issuanceBook: AddressBookOps,
  contractName: string,
): Promise<IntegrationCheck[]> {
  const checks: IntegrationCheck[] = []

  const rmAddress = horizonBook.entryExists('RewardsManager') ? horizonBook.getEntry('RewardsManager')?.address : null
  const contractAddress = issuanceBook.entryExists(contractName) ? issuanceBook.getEntry(contractName)?.address : null

  if (!rmAddress || !contractAddress) return checks

  // Find the reclaim reason for this contract
  const reclaimKey = Object.entries(RECLAIM_CONTRACT_NAMES).find(([_, name]) => name === contractName)?.[0] as
    | ReclaimReasonKey
    | undefined
  if (!reclaimKey) return checks

  const reason = RECLAIM_REASONS[reclaimKey]
  const actualAddress = await getReclaimAddress(client, rmAddress, reason)
  const configured = actualAddress?.toLowerCase() === contractAddress.toLowerCase()
  checks.push({ ok: configured, label: 'configured in RM.reclaimAddresses' })

  return checks
}

const deployStatusTask = task('deploy:status', 'Show deployment and integration status')
  .addOption({
    name: 'package',
    description: 'Show only specific package (horizon|subgraph-service|issuance|all)',
    type: ArgumentType.STRING,
    defaultValue: 'all',
  })
  .setAction(async () => ({ default: action }))
  .build()

export default deployStatusTask
