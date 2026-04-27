/**
 * Status Detail - Detailed contract status with integration checks
 *
 * Extracted from deployment-status task so deploy scripts (10_status.ts)
 * can show the same detail view. The task delegates to these functions.
 */

import type { Environment } from '@rocketh/core/types'
import type { PublicClient } from 'viem'

import {
  ACCESS_CONTROL_ENUMERABLE_ABI,
  CONTROLLER_ABI,
  IISSUANCE_TARGET_INTERFACE_ID,
  IREWARDS_MANAGER_INTERFACE_ID,
  ISSUANCE_ALLOCATOR_ABI,
  ISSUANCE_TARGET_ABI,
  PROVIDER_ELIGIBILITY_MANAGEMENT_ABI,
  REWARDS_ELIGIBILITY_ORACLE_ABI,
  REWARDS_MANAGER_ABI,
} from './abis.js'
import type { AddressBookOps } from './address-book-ops.js'
import { getTargetChainIdFromEnv } from './address-book-utils.js'
import {
  checkIssuanceAllocatorActivation,
  checkOperatorRole,
  formatAddress,
  supportsInterface,
} from './contract-checks.js'
import type { RegistryEntry } from './contract-registry.js'
import { countPendingGovernanceTxs } from './execute-governance.js'
import { formatGRT } from './format.js'
import { getContractStatusLine, type ContractStatusResult, type ProxyAdminOwnershipContext } from './sync-utils.js'
import { graph } from '../rocketh/deploy.js'

// ============================================================================
// Integration Check Types & Helpers
// ============================================================================

/** Integration check result */
export interface IntegrationCheck {
  ok: boolean | null // null = not applicable / not deployed
  label: string
}

function formatCheck(check: IntegrationCheck): string {
  const icon = check.ok === null ? '○' : check.ok ? '✓' : '✗'
  return `        ${icon} ${check.label}`
}

function formatWarnings(warnings: string[] | undefined): string[] {
  if (!warnings) return []
  return warnings.map((w) => `      ⚠ ${w}`)
}

/** Format proxy admin detail lines */
function formatProxyAdminDetail(result: ContractStatusResult): string[] {
  if (!result.proxyAdminAddress) return []
  const lines: string[] = []
  const ownerIcon = result.proxyAdminOwner === 'governor' ? '✓' : result.proxyAdminOwner === 'unknown' ? '○' : '⚠'
  const ownerRole =
    result.proxyAdminOwner === 'governor'
      ? 'governor'
      : result.proxyAdminOwner === 'deployer'
        ? 'deployer'
        : result.proxyAdminOwner === 'other'
          ? 'not governor'
          : 'unknown'
  const ownerAddr = result.proxyAdminOwnerAddress ? ` ${result.proxyAdminOwnerAddress}` : ''
  lines.push(`        ProxyAdmin: ${result.proxyAdminAddress}`)
  lines.push(`        ${ownerIcon} ProxyAdmin owner:${ownerAddr} (${ownerRole})`)
  return lines
}

// ============================================================================
// Ownership Context Resolution
// ============================================================================

/**
 * Resolve governor/deployer context for proxy admin ownership checks
 */
export async function resolveOwnershipContext(
  client: PublicClient,
  env: Environment,
  chainId: number,
): Promise<ProxyAdminOwnershipContext | undefined> {
  const horizonAddressBook = graph.getHorizonAddressBook(chainId)
  try {
    const controllerAddress = horizonAddressBook.entryExists('Controller')
      ? horizonAddressBook.getEntry('Controller')?.address
      : null
    if (!controllerAddress) return undefined

    const governor = (await client.readContract({
      address: controllerAddress as `0x${string}`,
      abi: CONTROLLER_ABI,
      functionName: 'getGovernor',
    })) as string

    if (!governor) return undefined

    // Deployer is best-effort: available when provider has accounts (fork/local)
    let deployer: string | undefined
    try {
      const accounts = (await env.network.provider.request({ method: 'eth_accounts' })) as string[] | undefined
      if (accounts && accounts.length > 0) {
        deployer = accounts[0]
      }
    } catch {
      // No accounts available (read-only provider)
    }

    return { governor, deployer }
  } catch {
    return undefined
  }
}

// ============================================================================
// Integration Check Functions
// ============================================================================

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'

export async function getRewardsManagerChecks(
  client: PublicClient,
  horizonBook: AddressBookOps,
  issuanceBook?: AddressBookOps,
  ssBook?: AddressBookOps,
): Promise<IntegrationCheck[]> {
  const checks: IntegrationCheck[] = []
  const rmAddress = horizonBook.entryExists('RewardsManager') ? horizonBook.getEntry('RewardsManager')?.address : null

  if (!rmAddress) return checks

  // Interface support
  const supportsRewardsManager = await supportsInterface(client, rmAddress, IREWARDS_MANAGER_INTERFACE_ID)
  checks.push({ ok: supportsRewardsManager, label: `implements IRewardsManager (${IREWARDS_MANAGER_INTERFACE_ID})` })

  const supportsIssuanceTarget = await supportsInterface(client, rmAddress, IISSUANCE_TARGET_INTERFACE_ID)
  checks.push({ ok: supportsIssuanceTarget, label: `implements IIssuanceTarget (${IISSUANCE_TARGET_INTERFACE_ID})` })

  if (!supportsRewardsManager) return checks

  // Helper: read a contract value, returning null on failure
  async function rmRead<T>(functionName: string, abi: readonly unknown[] = REWARDS_MANAGER_ABI): Promise<T | null> {
    try {
      return (await client.readContract({
        address: rmAddress as `0x${string}`,
        abi,
        functionName,
      })) as T
    } catch {
      return null
    }
  }

  // Issuance rates
  const rawRate = await rmRead<bigint>('getRawIssuancePerBlock')
  const allocatedRate = await rmRead<bigint>('getAllocatedIssuancePerBlock')
  if (rawRate !== null) {
    checks.push({ ok: rawRate > 0n, label: `issuancePerBlock: ${formatGRT(rawRate)} (raw)` })
  }
  if (allocatedRate !== null) {
    checks.push({
      ok: allocatedRate > 0n,
      label: `issuancePerBlock: ${formatGRT(allocatedRate)} (after IA allocation)`,
    })
  }

  // SubgraphService
  const ss = await rmRead<string>('subgraphService')
  if (ss !== null) {
    const expected = ssBook?.entryExists('SubgraphService')
      ? (ssBook.getEntry('SubgraphService')?.address ?? null)
      : null
    const matches = expected ? ss.toLowerCase() === expected.toLowerCase() : null
    checks.push({
      ok: ss !== ZERO_ADDRESS ? matches : false,
      label: `subgraphService: ${ss}${matches === false && expected ? ` (expected ${expected})` : ''}`,
    })
  }

  // IssuanceAllocator
  const ia = await rmRead<string>('getIssuanceAllocator', ISSUANCE_TARGET_ABI)
  if (ia !== null) {
    const iaBook = issuanceBook?.entryExists('IssuanceAllocator')
      ? issuanceBook.getEntry('IssuanceAllocator')?.address
      : null
    const isSet = ia !== ZERO_ADDRESS
    const matches = iaBook ? ia.toLowerCase() === iaBook.toLowerCase() : null
    checks.push({
      ok: isSet ? matches : null,
      label: isSet
        ? `issuanceAllocator: ${ia}${matches === false ? ` (expected ${iaBook!})` : ''}`
        : 'issuanceAllocator: not set',
    })
  }

  // Provider eligibility oracle
  const reo = await rmRead<string>('getProviderEligibilityOracle', PROVIDER_ELIGIBILITY_MANAGEMENT_ABI)
  if (reo !== null) {
    const reoA = issuanceBook?.entryExists('RewardsEligibilityOracleA')
      ? issuanceBook.getEntry('RewardsEligibilityOracleA')?.address
      : null
    const isSet = reo !== ZERO_ADDRESS
    const matchesA = reoA ? reo.toLowerCase() === reoA.toLowerCase() : null
    checks.push({
      ok: isSet ? matchesA : null,
      label: isSet
        ? `providerEligibilityOracle: ${reo}${matchesA === false ? ' (not REO-A)' : matchesA ? ' (REO-A)' : ''}`
        : 'providerEligibilityOracle: not set',
    })
  } else {
    checks.push({ ok: null, label: 'providerEligibilityOracle: not set' })
  }

  // Revert on ineligible
  const revertOnIneligible = await rmRead<boolean>('getRevertOnIneligible')
  if (revertOnIneligible !== null) {
    checks.push({ ok: null, label: `revertOnIneligible: ${revertOnIneligible}` })
  }

  // Default reclaim address
  const defaultReclaim = await rmRead<string>('getDefaultReclaimAddress')
  if (defaultReclaim !== null) {
    const expectedAddr = issuanceBook?.entryExists('ReclaimedRewards')
      ? issuanceBook.getEntry('ReclaimedRewards')?.address
      : null
    const isSet = defaultReclaim !== ZERO_ADDRESS
    const matches = isSet && expectedAddr ? defaultReclaim.toLowerCase() === expectedAddr.toLowerCase() : null
    checks.push({
      ok: isSet ? (matches ?? true) : null,
      label: isSet
        ? `defaultReclaimAddress: ${defaultReclaim}${matches === false ? ` (expected ${expectedAddr!})` : ''}`
        : 'defaultReclaimAddress: not set',
    })
  }

  return checks
}

export async function getIssuanceAllocatorChecks(
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

  const rmSupportsTarget = await supportsInterface(client, rmAddress, IISSUANCE_TARGET_INTERFACE_ID)
  checks.push({ ok: rmSupportsTarget, label: `RM implements IIssuanceTarget (${IISSUANCE_TARGET_INTERFACE_ID})` })

  if (rmSupportsTarget) {
    const activation = await checkIssuanceAllocatorActivation(client, iaAddress, rmAddress, gtAddress)
    checks.push({ ok: activation.iaIntegrated, label: 'RM.issuanceAllocator == this' })
    checks.push({ ok: activation.iaMinter, label: 'GraphToken.MINTER_ROLE granted' })
  } else {
    checks.push({ ok: null, label: 'RM.issuanceAllocator == this (RM not upgraded)' })
    checks.push({ ok: null, label: 'GraphToken.MINTER_ROLE granted (RM not upgraded)' })
  }

  try {
    const targetCount = (await client.readContract({
      address: iaAddress as `0x${string}`,
      abi: ISSUANCE_ALLOCATOR_ABI,
      functionName: 'getTargetCount',
    })) as bigint
    const hasDefaultTarget = targetCount > 0n
    checks.push({ ok: hasDefaultTarget, label: 'defaultTarget configured' })
  } catch {
    // Function not available
  }

  // Confirm 100% allocation: getTotalAllocation().totalAllocationRate == issuancePerBlock.
  // Once a real defaultTarget is set (issuance-connect), the contract reports
  // exactly issuancePerBlock; if it doesn't, the default is still address(0)
  // and some issuance is unallocated (not minted). Skipped (○) when
  // issuancePerBlock is 0 — the IA hasn't been configured with a rate yet,
  // so the question is not yet meaningful.
  try {
    const issuancePerBlock = (await client.readContract({
      address: iaAddress as `0x${string}`,
      abi: ISSUANCE_ALLOCATOR_ABI,
      functionName: 'getIssuancePerBlock',
    })) as bigint
    const totalAllocation = (await client.readContract({
      address: iaAddress as `0x${string}`,
      abi: ISSUANCE_ALLOCATOR_ABI,
      functionName: 'getTotalAllocation',
    })) as { totalAllocationRate: bigint; allocatorMintingRate: bigint; selfMintingRate: bigint }
    if (issuancePerBlock === 0n) {
      checks.push({ ok: null, label: '100% allocated (issuancePerBlock not set)' })
    } else {
      const fullyAllocated = totalAllocation.totalAllocationRate === issuancePerBlock
      checks.push({
        ok: fullyAllocated,
        label: `100% allocated (${formatGRT(totalAllocation.totalAllocationRate)} of ${formatGRT(issuancePerBlock)})`,
      })
    }
  } catch {
    // Function not available
  }

  return checks
}

export async function getRewardsEligibilityOracleChecks(
  client: PublicClient,
  horizonBook: AddressBookOps,
  issuanceBook: AddressBookOps,
  entryName: string,
): Promise<IntegrationCheck[]> {
  const checks: IntegrationCheck[] = []

  const reoAddress = issuanceBook.entryExists(entryName) ? issuanceBook.getEntry(entryName)?.address : null
  const rmAddress = horizonBook.entryExists('RewardsManager') ? horizonBook.getEntry('RewardsManager')?.address : null
  const controllerAddress = horizonBook.entryExists('Controller') ? horizonBook.getEntry('Controller')?.address : null

  if (!reoAddress || !rmAddress) return checks

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

  const networkOperator = issuanceBook.entryExists('NetworkOperator')
    ? (issuanceBook.getEntry('NetworkOperator')?.address ?? null)
    : null

  try {
    const operatorCheck = await checkOperatorRole(client, reoAddress, networkOperator)
    const statusOk = networkOperator === null ? false : operatorCheck.ok
    checks.push({ ok: statusOk, label: operatorCheck.message })
  } catch {
    checks.push({ ok: null, label: 'OPERATOR_ROLE (check failed)' })
  }

  try {
    const currentREO = (await client.readContract({
      address: rmAddress as `0x${string}`,
      abi: PROVIDER_ELIGIBILITY_MANAGEMENT_ABI,
      functionName: 'getProviderEligibilityOracle',
    })) as string
    const configured = currentREO.toLowerCase() === reoAddress.toLowerCase()
    checks.push({ ok: configured, label: 'RM.providerEligibilityOracle == this' })
  } catch {
    // Function not available on old RM
  }

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

export async function getReclaimAddressChecks(
  client: PublicClient,
  horizonBook: AddressBookOps,
  issuanceBook: AddressBookOps,
): Promise<IntegrationCheck[]> {
  const checks: IntegrationCheck[] = []

  const rmAddress = horizonBook.entryExists('RewardsManager') ? horizonBook.getEntry('RewardsManager')?.address : null
  const reclaimAddress = issuanceBook.entryExists('ReclaimedRewards')
    ? issuanceBook.getEntry('ReclaimedRewards')?.address
    : null

  if (!rmAddress || !reclaimAddress) return checks

  try {
    const defaultReclaim = (await client.readContract({
      address: rmAddress as `0x${string}`,
      abi: REWARDS_MANAGER_ABI,
      functionName: 'getDefaultReclaimAddress',
    })) as string
    const configured = defaultReclaim.toLowerCase() === reclaimAddress.toLowerCase()
    checks.push({ ok: configured, label: 'configured as RM.defaultReclaimAddress' })
  } catch {
    checks.push({ ok: false, label: 'configured as RM.defaultReclaimAddress' })
  }

  return checks
}

// Minimal ABI for RecurringAgreementManager-specific view functions
const RECURRING_AGREEMENT_MANAGER_ABI = [
  {
    inputs: [],
    name: 'COLLECTOR_ROLE',
    outputs: [{ type: 'bytes32' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'DATA_SERVICE_ROLE',
    outputs: [{ type: 'bytes32' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'getCollectorCount',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'paused',
    outputs: [{ type: 'bool' }],
    stateMutability: 'view',
    type: 'function',
  },
] as const

export async function getRecurringAgreementManagerChecks(
  client: PublicClient,
  horizonBook: AddressBookOps,
  issuanceBook: AddressBookOps,
  ssBook: AddressBookOps,
): Promise<IntegrationCheck[]> {
  const checks: IntegrationCheck[] = []

  const ramAddress = issuanceBook.entryExists('RecurringAgreementManager')
    ? issuanceBook.getEntry('RecurringAgreementManager')?.address
    : null
  if (!ramAddress) return checks

  // COLLECTOR_ROLE → RecurringCollector
  const rcAddress = horizonBook.entryExists('RecurringCollector')
    ? horizonBook.getEntry('RecurringCollector')?.address
    : null
  if (rcAddress) {
    try {
      const collectorRole = (await client.readContract({
        address: ramAddress as `0x${string}`,
        abi: RECURRING_AGREEMENT_MANAGER_ABI,
        functionName: 'COLLECTOR_ROLE',
      })) as `0x${string}`
      const hasRole = (await client.readContract({
        address: ramAddress as `0x${string}`,
        abi: ACCESS_CONTROL_ENUMERABLE_ABI,
        functionName: 'hasRole',
        args: [collectorRole, rcAddress as `0x${string}`],
      })) as boolean
      checks.push({ ok: hasRole, label: 'RecurringCollector has COLLECTOR_ROLE' })
    } catch {
      // Role check not available
    }
  }

  // DATA_SERVICE_ROLE → SubgraphService
  const ssAddress = ssBook?.entryExists('SubgraphService') ? ssBook.getEntry('SubgraphService')?.address : null
  if (ssAddress) {
    try {
      const dataServiceRole = (await client.readContract({
        address: ramAddress as `0x${string}`,
        abi: RECURRING_AGREEMENT_MANAGER_ABI,
        functionName: 'DATA_SERVICE_ROLE',
      })) as `0x${string}`
      const hasRole = (await client.readContract({
        address: ramAddress as `0x${string}`,
        abi: ACCESS_CONTROL_ENUMERABLE_ABI,
        functionName: 'hasRole',
        args: [dataServiceRole, ssAddress as `0x${string}`],
      })) as boolean
      checks.push({ ok: hasRole, label: 'SubgraphService has DATA_SERVICE_ROLE' })
    } catch {
      // Role check not available
    }
  }

  // IssuanceAllocator
  const iaAddress = issuanceBook.entryExists('IssuanceAllocator')
    ? issuanceBook.getEntry('IssuanceAllocator')?.address
    : null
  try {
    const currentIA = (await client.readContract({
      address: ramAddress as `0x${string}`,
      abi: ISSUANCE_TARGET_ABI,
      functionName: 'getIssuanceAllocator',
    })) as string
    const isSet = currentIA !== ZERO_ADDRESS
    const matches = iaAddress ? currentIA.toLowerCase() === iaAddress.toLowerCase() : null
    checks.push({
      ok: isSet ? matches : false,
      label: isSet
        ? `issuanceAllocator: ${formatAddress(currentIA)}${matches === false ? ` (expected ${formatAddress(iaAddress!)})` : ''}`
        : 'issuanceAllocator: not set',
    })
  } catch {
    // Function not available
  }

  // Provider eligibility oracle
  try {
    const reo = (await client.readContract({
      address: ramAddress as `0x${string}`,
      abi: PROVIDER_ELIGIBILITY_MANAGEMENT_ABI,
      functionName: 'getProviderEligibilityOracle',
    })) as string
    const reoA = issuanceBook.entryExists('RewardsEligibilityOracleA')
      ? issuanceBook.getEntry('RewardsEligibilityOracleA')?.address
      : null
    const isSet = reo !== ZERO_ADDRESS
    const matchesA = reoA ? reo.toLowerCase() === reoA.toLowerCase() : null
    checks.push({
      ok: isSet ? matchesA : null,
      label: isSet
        ? `providerEligibilityOracle: ${reo}${matchesA === false ? ' (not REO-A)' : matchesA ? ' (REO-A)' : ''}`
        : 'providerEligibilityOracle: not set',
    })
  } catch {
    // Function not available
  }

  // Paused state
  try {
    const paused = (await client.readContract({
      address: ramAddress as `0x${string}`,
      abi: RECURRING_AGREEMENT_MANAGER_ABI,
      functionName: 'paused',
    })) as boolean
    checks.push({ ok: !paused, label: paused ? 'PAUSED' : 'not paused' })
  } catch {
    // Function not available
  }

  // Collector count
  try {
    const count = (await client.readContract({
      address: ramAddress as `0x${string}`,
      abi: RECURRING_AGREEMENT_MANAGER_ABI,
      functionName: 'getCollectorCount',
    })) as bigint
    checks.push({ ok: null, label: `collectors: ${count}` })
  } catch {
    // Function not available
  }

  return checks
}

// ============================================================================
// Horizon / SubgraphService Contract Checks
// ============================================================================

// Minimal ABIs for contracts not in the abis.ts module
const PAUSABLE_ABI = [
  { inputs: [], name: 'paused', outputs: [{ type: 'bool' }], stateMutability: 'view', type: 'function' },
] as const

const PAUSE_GUARDIAN_ABI = [
  {
    inputs: [{ name: '_pauseGuardian', type: 'address' }],
    name: 'pauseGuardians',
    outputs: [{ type: 'bool' }],
    stateMutability: 'view',
    type: 'function',
  },
] as const

const DISPUTE_MANAGER_ABI = [
  { inputs: [], name: 'arbitrator', outputs: [{ type: 'address' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'getDisputePeriod', outputs: [{ type: 'uint64' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'disputeDeposit', outputs: [{ type: 'uint256' }], stateMutability: 'view', type: 'function' },
  {
    inputs: [],
    name: 'getFishermanRewardCut',
    outputs: [{ type: 'uint32' }],
    stateMutability: 'view',
    type: 'function',
  },
  { inputs: [], name: 'maxSlashingCut', outputs: [{ type: 'uint32' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'subgraphService', outputs: [{ type: 'address' }], stateMutability: 'view', type: 'function' },
] as const

const SUBGRAPH_SERVICE_ABI = [
  {
    inputs: [],
    name: 'getProvisionTokensRange',
    outputs: [{ type: 'uint256' }, { type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'getDelegationRatio',
    outputs: [{ type: 'uint32' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'stakeToFeesRatio',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'curationFeesCut',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'getDisputeManager',
    outputs: [{ type: 'address' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'getGraphTallyCollector',
    outputs: [{ type: 'address' }],
    stateMutability: 'view',
    type: 'function',
  },
  { inputs: [], name: 'getCuration', outputs: [{ type: 'address' }], stateMutability: 'view', type: 'function' },
] as const

/** PPM denominator (1,000,000) for percentage display */
const PPM = 1_000_000

export async function getRecurringCollectorChecks(
  client: PublicClient,
  address: string,
  horizonBook: AddressBookOps,
): Promise<IntegrationCheck[]> {
  const checks: IntegrationCheck[] = []

  // Pause guardian
  try {
    const controllerAddress = horizonBook.entryExists('Controller') ? horizonBook.getEntry('Controller')?.address : null
    if (controllerAddress) {
      // pauseGuardian is a public storage variable auto-getter, not in IControllerToolshed
      const pauseGuardian = (await client.readContract({
        address: controllerAddress as `0x${string}`,
        abi: [
          {
            inputs: [],
            name: 'pauseGuardian',
            outputs: [{ internalType: 'address', name: '', type: 'address' }],
            stateMutability: 'view',
            type: 'function',
          },
        ] as const,
        functionName: 'pauseGuardian',
      })) as string
      const isGuardian = (await client.readContract({
        address: address as `0x${string}`,
        abi: PAUSE_GUARDIAN_ABI,
        functionName: 'pauseGuardians',
        args: [pauseGuardian as `0x${string}`],
      })) as boolean
      checks.push({ ok: isGuardian, label: `pauseGuardian: ${pauseGuardian} ${isGuardian ? '' : '(not set)'}` })
    }
  } catch {
    // Not available
  }

  // Paused state
  try {
    const paused = (await client.readContract({
      address: address as `0x${string}`,
      abi: PAUSABLE_ABI,
      functionName: 'paused',
    })) as boolean
    checks.push({ ok: !paused, label: paused ? 'PAUSED' : 'not paused' })
  } catch {
    // paused() not available
  }

  // Thawing period
  try {
    const thawing = (await client.readContract({
      address: address as `0x${string}`,
      abi: [
        {
          inputs: [],
          name: 'REVOKE_AUTHORIZATION_THAWING_PERIOD',
          outputs: [{ type: 'uint256' }],
          stateMutability: 'view',
          type: 'function',
        },
      ],
      functionName: 'REVOKE_AUTHORIZATION_THAWING_PERIOD',
    })) as bigint
    checks.push({ ok: null, label: `REVOKE_AUTHORIZATION_THAWING_PERIOD: ${thawing}` })
  } catch {
    // Not available
  }

  return checks
}

export async function getDisputeManagerChecks(
  client: PublicClient,
  address: string,
  horizonBook: AddressBookOps,
  ssBook: AddressBookOps,
): Promise<IntegrationCheck[]> {
  const checks: IntegrationCheck[] = []

  async function dmRead<T>(functionName: (typeof DISPUTE_MANAGER_ABI)[number]['name']): Promise<T | null> {
    try {
      return (await client.readContract({
        address: address as `0x${string}`,
        abi: DISPUTE_MANAGER_ABI,
        functionName,
      })) as T
    } catch {
      return null
    }
  }

  // Arbitrator
  const arbitrator = await dmRead<string>('arbitrator')
  if (arbitrator !== null) {
    checks.push({ ok: arbitrator !== ZERO_ADDRESS, label: `arbitrator: ${arbitrator}` })
  }

  // SubgraphService reference
  const ss = await dmRead<string>('subgraphService')
  if (ss !== null) {
    const expected = ssBook?.entryExists('SubgraphService')
      ? (ssBook.getEntry('SubgraphService')?.address ?? null)
      : null
    const matches = expected ? ss.toLowerCase() === expected.toLowerCase() : null
    checks.push({
      ok: ss !== ZERO_ADDRESS ? matches : false,
      label: `subgraphService: ${ss}${matches === false && expected ? ` (expected ${expected})` : ''}`,
    })
  }

  // Dispute period
  const disputePeriod = await dmRead<bigint>('getDisputePeriod')
  if (disputePeriod !== null) {
    checks.push({ ok: disputePeriod > 0n, label: `disputePeriod: ${disputePeriod}s` })
  }

  // Dispute deposit
  const disputeDeposit = await dmRead<bigint>('disputeDeposit')
  if (disputeDeposit !== null) {
    checks.push({ ok: disputeDeposit > 0n, label: `disputeDeposit: ${formatGRT(disputeDeposit)}` })
  }

  // Fisherman reward cut (PPM)
  const fishermanCut = await dmRead<number>('getFishermanRewardCut')
  if (fishermanCut !== null) {
    checks.push({
      ok: null,
      label: `fishermanRewardCut: ${fishermanCut} (${((fishermanCut / PPM) * 100).toFixed(2)}%)`,
    })
  }

  // Max slashing cut (PPM)
  const maxSlashing = await dmRead<number>('maxSlashingCut')
  if (maxSlashing !== null) {
    checks.push({ ok: null, label: `maxSlashingCut: ${maxSlashing} (${((maxSlashing / PPM) * 100).toFixed(2)}%)` })
  }

  return checks
}

export async function getSubgraphServiceChecks(
  client: PublicClient,
  address: string,
  horizonBook: AddressBookOps,
  ssBook: AddressBookOps,
): Promise<IntegrationCheck[]> {
  const checks: IntegrationCheck[] = []

  async function ssRead<T>(functionName: (typeof SUBGRAPH_SERVICE_ABI)[number]['name']): Promise<T | null> {
    try {
      return (await client.readContract({
        address: address as `0x${string}`,
        abi: SUBGRAPH_SERVICE_ABI,
        functionName,
      })) as T
    } catch {
      return null
    }
  }

  // DisputeManager reference
  const dm = await ssRead<string>('getDisputeManager')
  if (dm !== null) {
    const expected = ssBook?.entryExists('DisputeManager') ? (ssBook.getEntry('DisputeManager')?.address ?? null) : null
    const matches = expected ? dm.toLowerCase() === expected.toLowerCase() : null
    checks.push({
      ok: dm !== ZERO_ADDRESS ? matches : false,
      label: `disputeManager: ${dm}${matches === false && expected ? ` (expected ${expected})` : ''}`,
    })
  }

  // GraphTallyCollector reference
  const gtc = await ssRead<string>('getGraphTallyCollector')
  if (gtc !== null) {
    const expected = horizonBook.entryExists('GraphTallyCollector')
      ? (horizonBook.getEntry('GraphTallyCollector')?.address ?? null)
      : null
    const matches = expected ? gtc.toLowerCase() === expected.toLowerCase() : null
    checks.push({
      ok: gtc !== ZERO_ADDRESS ? matches : false,
      label: `graphTallyCollector: ${gtc}${matches === false && expected ? ` (expected ${expected})` : ''}`,
    })
  }

  // Curation reference
  const curation = await ssRead<string>('getCuration')
  if (curation !== null) {
    const expected = horizonBook.entryExists('L2Curation')
      ? (horizonBook.getEntry('L2Curation')?.address ?? null)
      : null
    const matches = expected ? curation.toLowerCase() === expected.toLowerCase() : null
    checks.push({
      ok: curation !== ZERO_ADDRESS ? matches : false,
      label: `curation: ${curation}${matches === false && expected ? ` (expected ${expected})` : ''}`,
    })
  }

  // Provision tokens range
  const provisionRange = await ssRead<readonly [bigint, bigint]>('getProvisionTokensRange')
  if (provisionRange !== null) {
    checks.push({
      ok: null,
      label: `provisionTokensRange: [${formatGRT(provisionRange[0])}, ${formatGRT(provisionRange[1])}]`,
    })
  }

  // Delegation ratio
  const delegationRatio = await ssRead<number>('getDelegationRatio')
  if (delegationRatio !== null) {
    checks.push({ ok: null, label: `delegationRatio: ${delegationRatio}` })
  }

  // Stake to fees ratio
  const stakeToFees = await ssRead<bigint>('stakeToFeesRatio')
  if (stakeToFees !== null) {
    checks.push({ ok: null, label: `stakeToFeesRatio: ${stakeToFees}` })
  }

  // Curation fees cut (PPM)
  const curationCut = await ssRead<bigint>('curationFeesCut')
  if (curationCut !== null) {
    checks.push({
      ok: null,
      label: `curationFeesCut: ${curationCut} (${((Number(curationCut) / PPM) * 100).toFixed(2)}%)`,
    })
  }

  return checks
}

// ============================================================================
// High-Level Status Display
// ============================================================================

/**
 * Show detailed status for a single component from the registry.
 *
 * Displays: status line + proxy admin detail + contract-specific integration checks.
 * This is the detail view shown when running `--tags IssuanceAllocator`.
 */
export async function showDetailedComponentStatus(
  env: Environment,
  contract: RegistryEntry,
  options?: { showHints?: boolean },
): Promise<ContractStatusResult> {
  const chainId = await getTargetChainIdFromEnv(env)
  const client = graph.getPublicClient(env) as PublicClient

  // Resolve address books
  const horizonBook = graph.getHorizonAddressBook(chainId)
  const addressBook =
    contract.addressBook === 'horizon'
      ? horizonBook
      : contract.addressBook === 'subgraph-service'
        ? graph.getSubgraphServiceAddressBook(chainId)
        : graph.getIssuanceAddressBook(chainId)

  // Resolve ownership context
  const ownershipCtx = await resolveOwnershipContext(client, env, chainId)

  // Get status line with detail
  const result = await getContractStatusLine(
    client,
    contract.addressBook,
    addressBook,
    contract.name,
    undefined,
    ownershipCtx,
  )
  env.showMessage(`  ${result.line}`)
  for (const line of formatWarnings(result.warnings)) {
    env.showMessage(line)
  }
  // Show ProxyAdmin detail for OZ v5 transparent proxies (not old Graph proxies,
  // which are controller-governed and don't expose owner())
  if (contract.proxyType !== 'graph') {
    for (const line of formatProxyAdminDetail(result)) {
      env.showMessage(line)
    }
  }

  // Verification status from address book
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  if (result.exists && (addressBook as any).entryExists(contract.name)) {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const entry = (addressBook as any).getEntry(contract.name)
    if (entry.proxy) {
      const proxyVerified = entry.proxyDeployment?.verified
      const implVerified = entry.implementationDeployment?.verified
      env.showMessage(`        ${proxyVerified ? '✓' : '✗'} proxy verified${proxyVerified ? `: ${proxyVerified}` : ''}`)
      env.showMessage(`        ${implVerified ? '✓' : '✗'} impl verified${implVerified ? `: ${implVerified}` : ''}`)
    } else {
      const verified = entry.deployment?.verified
      env.showMessage(`        ${verified ? '✓' : '✗'} verified${verified ? `: ${verified}` : ''}`)
    }
  }

  const showHints = options?.showHints !== false

  // Contract-specific integration checks
  if (!result.exists) {
    if (showHints && contract.componentTag && contract.deployable) {
      showLifecycleHints(env, contract, result)
    }
    return result
  }

  const issuanceBook = contract.addressBook === 'issuance' ? addressBook : graph.getIssuanceAddressBook(chainId)

  let checks: IntegrationCheck[] = []
  if (contract.name === 'RewardsManager') {
    checks = await getRewardsManagerChecks(
      client,
      horizonBook,
      issuanceBook,
      graph.getSubgraphServiceAddressBook(chainId),
    )
  } else if (contract.name === 'IssuanceAllocator') {
    checks = await getIssuanceAllocatorChecks(client, horizonBook, issuanceBook)
  } else if (
    contract.name === 'RewardsEligibilityOracleA' ||
    contract.name === 'RewardsEligibilityOracleB' ||
    contract.name === 'RewardsEligibilityOracleMock'
  ) {
    checks = await getRewardsEligibilityOracleChecks(client, horizonBook, issuanceBook, contract.name)
  } else if (contract.name === 'RecurringAgreementManager') {
    checks = await getRecurringAgreementManagerChecks(
      client,
      horizonBook,
      issuanceBook,
      graph.getSubgraphServiceAddressBook(chainId),
    )
  } else if (contract.name === 'ReclaimedRewards') {
    checks = await getReclaimAddressChecks(client, horizonBook, issuanceBook)
  } else if (contract.name === 'RecurringCollector') {
    const addr = horizonBook.entryExists('RecurringCollector')
      ? horizonBook.getEntry('RecurringCollector')?.address
      : null
    if (addr) checks = await getRecurringCollectorChecks(client, addr, horizonBook)
  } else if (contract.name === 'DisputeManager') {
    const ssBook = graph.getSubgraphServiceAddressBook(chainId)
    const addr = ssBook.entryExists('DisputeManager') ? ssBook.getEntry('DisputeManager')?.address : null
    if (addr) checks = await getDisputeManagerChecks(client, addr, horizonBook, ssBook)
  } else if (contract.name === 'SubgraphService') {
    const ssBook = graph.getSubgraphServiceAddressBook(chainId)
    const addr = ssBook.entryExists('SubgraphService') ? ssBook.getEntry('SubgraphService')?.address : null
    if (addr) checks = await getSubgraphServiceChecks(client, addr, horizonBook, ssBook)
  }

  for (const check of checks) {
    env.showMessage(formatCheck(check))
  }

  // Lifecycle action hints
  if (showHints && contract.componentTag && contract.deployable) {
    showLifecycleHints(env, contract, result)
  }

  return result
}

/**
 * Show available lifecycle actions and state-based hint for a component.
 */
function showLifecycleHints(env: Environment, contract: RegistryEntry, result: ContractStatusResult): void {
  const tag = contract.componentTag!

  // State-based hint
  if (!result.exists) {
    env.showMessage(`\n  → Not deployed. Run with: --tags ${tag},deploy`)
  } else if (result.codeChanged && !result.hasPendingImplementation) {
    env.showMessage(`\n  → Code changed. Run with: --tags ${tag},deploy`)
  } else if (result.hasPendingImplementation) {
    env.showMessage(`\n  → Pending implementation. Run with: --tags ${tag},upgrade`)
  } else {
    env.showMessage(`\n  → Up to date`)
  }

  // Available actions — use explicit list if provided, otherwise derive from metadata
  let actions: readonly string[]
  if (contract.lifecycleActions) {
    actions = contract.lifecycleActions
  } else {
    const derived: string[] = ['deploy']
    if (contract.proxyType) derived.push('upgrade')
    actions = derived
  }
  env.showMessage(`  Actions: --tags ${tag},<${[...actions, 'all'].join('|')}>`)
}

/**
 * Show pending governance TX count with execute command if any exist.
 * Call once at the end of a status display, not per-component.
 */
export function showPendingGovernanceTxs(env: Environment): void {
  const count = countPendingGovernanceTxs(env.name)
  if (count > 0) {
    env.showMessage(`\n  ⚠ ${count} pending governance TX(s)`)
    env.showMessage(`    Run: npx hardhat deploy:execute-governance --network ${env.name}`)
  }
}
