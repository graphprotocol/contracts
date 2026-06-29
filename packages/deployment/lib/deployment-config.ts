import { readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

import type { Environment } from '@rocketh/core/types'
import JSON5 from 'json5'
import { formatEther, parseUnits } from 'viem'

import { getTargetChainIdFromEnv } from './address-book-utils.js'
import {
  ALLOCATION_TARGET_CONTRACTS,
  type AllocationTargetContractName,
  ELIGIBILITY_ORACLE_CONTRACTS,
  type EligibilityOracleContractName,
} from './contract-registry.js'

const __dirname = dirname(fileURLToPath(import.meta.url))

/** Chain ID to config file name mapping */
const CHAIN_CONFIG_MAP: Record<number, string> = {
  1337: 'localNetwork',
  42161: 'arbitrumOne',
  421614: 'arbitrumSepolia',
}

/**
 * Raw on-disk shape of `config/<network>.json5`. Every field is optional —
 * networks override only what they need; the rest comes from `DEFAULT_SETTINGS`.
 */
interface DeploymentConfigFile {
  IssuanceAllocator?: {
    /** Expected total issuance/block (GRT). Scripts error if RM's on-chain value differs. */
    issuancePerBlock?: string
    /** Explicit allocation per target, keyed by full contract name. Rates default to '0'. */
    allocations?: Partial<
      Record<AllocationTargetContractName, { allocatorGrtPerBlock?: string; selfGrtPerBlock?: string }>
    >
  }
  RewardsManager?: {
    revertOnIneligible?: boolean
    /** Full contract name of the REO RM points at; omit for no oracle. */
    eligibilityOracle?: EligibilityOracleContractName
  }
  RecurringAgreementManager?: {
    /** Full contract name of the REO RAM points at; omit for no oracle. */
    eligibilityOracle?: EligibilityOracleContractName
  }
  RecurringCollector?: {
    revokeSignerThawingPeriod?: string
    eip712Name?: string
    eip712Version?: string
  }
  RewardsEligibilityOracle?: {
    /** Eligibility period in seconds — indexers fall out of eligibility this long after their last positive attestation. */
    eligibilityPeriod?: string
    /** Oracle update timeout in seconds — all indexers go ineligible after this long without an oracle update. */
    oracleUpdateTimeout?: string
  }
  SubgraphService?: {
    /**
     * When true, allocations with active indexing agreements cannot be closed.
     * Set by the `GIP-0088:issuance-close-guard` optional goal.
     */
    blockClosingAllocationWithActiveAgreement?: boolean
  }
}

/**
 * Fully-resolved deployment settings for a given chain.
 *
 * Defaults from `DEFAULT_SETTINGS` are applied for any field a network's config
 * file omits, so consumers read this directly without per-call `??` fallbacks.
 * Eligibility-oracle fields are the exception: they are `undefined` when the
 * network's config omits them, meaning "no oracle for this target" — there is
 * no hidden default, so the per-network json5 is the single source of truth.
 */
export interface ResolvedSettings {
  rewardsManager: {
    /** Revert on reward claim attempts by ineligible indexers. */
    revertOnIneligible: boolean
    /** REO contract RM is wired to; `undefined` means no oracle (config omitted it). */
    eligibilityOracle?: EligibilityOracleContractName
  }
  recurringAgreementManager: {
    /** REO contract RAM is wired to; `undefined` means no oracle (config omitted it). */
    eligibilityOracle?: EligibilityOracleContractName
  }
  issuanceAllocator: {
    /**
     * Expected total issuance/block (GRT), as a string. `undefined` when config
     * doesn't declare it. Scripts cross-check it against RM's on-chain value and
     * error on mismatch — they never set the rate from config.
     */
    issuancePerBlock?: string
    /**
     * Explicit per-target allocation. Each entry's rates sum (across all targets)
     * must equal `issuancePerBlock`. Empty when config declares no allocations.
     */
    allocations: Array<{
      target: AllocationTargetContractName
      allocatorGrtPerBlock: string
      selfGrtPerBlock: string
    }>
  }
  recurringCollector: {
    /** Signer revocation thaw period in seconds (constructor arg). */
    revokeSignerThawingPeriod: string
    /** EIP-712 domain name (init arg). */
    eip712Name: string
    /** EIP-712 domain version (init arg). */
    eip712Version: string
  }
  rewardsEligibilityOracle: {
    /** Eligibility period in seconds (REO `setEligibilityPeriod` arg). */
    eligibilityPeriod: bigint
    /** Oracle update timeout in seconds (REO `setOracleUpdateTimeout` arg). */
    oracleUpdateTimeout: bigint
  }
  subgraphService: {
    /** Desired value for `SS.setBlockClosingAllocationWithActiveAgreement`. */
    blockClosingAllocationWithActiveAgreement: boolean
  }
}

const DEFAULT_SETTINGS: ResolvedSettings = {
  // eligibilityOracle has no default — omission means "no oracle" (see below).
  rewardsManager: {
    revertOnIneligible: true,
  },
  recurringAgreementManager: {},
  issuanceAllocator: {
    // issuancePerBlock has no default; allocations default to none configured.
    allocations: [],
  },
  recurringCollector: {
    revokeSignerThawingPeriod: '28800', // ~1 day at 3s blocks
    eip712Name: 'RecurringCollector',
    eip712Version: '1',
  },
  rewardsEligibilityOracle: {
    eligibilityPeriod: 14n * 24n * 60n * 60n, // 14 days
    oracleUpdateTimeout: 7n * 24n * 60n * 60n, // 7 days
  },
  subgraphService: {
    blockClosingAllocationWithActiveAgreement: true,
  },
}

function loadConfigFile(chainId: number): DeploymentConfigFile {
  const networkName = CHAIN_CONFIG_MAP[chainId]
  if (!networkName) return {}

  const configPath = resolve(__dirname, '..', 'config', `${networkName}.json5`)
  try {
    const raw = readFileSync(configPath, 'utf-8')
    return JSON5.parse<DeploymentConfigFile>(raw)
  } catch {
    return {}
  }
}

/**
 * Validate an eligibility-oracle config value. `undefined` (config omitted the
 * field) is valid and means "no oracle for this target". A present-but-unknown
 * value is a config error — fail loud rather than silently dropping it.
 */
function resolveEligibilityOracle(
  value: string | undefined,
  field: string,
  chainId: number,
): EligibilityOracleContractName | undefined {
  if (value === undefined) return undefined
  if (!(ELIGIBILITY_ORACLE_CONTRACTS as readonly string[]).includes(value)) {
    throw new Error(
      `Invalid ${field}.eligibilityOracle "${value}" in config for chain ${chainId}; ` +
        `expected one of ${ELIGIBILITY_ORACLE_CONTRACTS.join(', ')} (or omit for no oracle)`,
    )
  }
  return value as EligibilityOracleContractName
}

/**
 * Resolve the per-target allocation map into an array, validating each key is a
 * known allocation target. Rates default to '0'. A present-but-unknown target
 * name is a config error — fail loud. Does NOT check the sum here; that needs
 * RM's on-chain rate and lives in the deploy/gate scripts.
 */
function resolveAllocations(
  raw:
    | Partial<Record<AllocationTargetContractName, { allocatorGrtPerBlock?: string; selfGrtPerBlock?: string }>>
    | undefined,
  chainId: number,
): ResolvedSettings['issuanceAllocator']['allocations'] {
  if (!raw) return []
  return Object.entries(raw).map(([target, rates]) => {
    if (!(ALLOCATION_TARGET_CONTRACTS as readonly string[]).includes(target)) {
      throw new Error(
        `Invalid IssuanceAllocator.allocations target "${target}" in config for chain ${chainId}; ` +
          `expected one of ${ALLOCATION_TARGET_CONTRACTS.join(', ')}`,
      )
    }
    return {
      target: target as AllocationTargetContractName,
      allocatorGrtPerBlock: rates?.allocatorGrtPerBlock ?? '0',
      selfGrtPerBlock: rates?.selfGrtPerBlock ?? '0',
    }
  })
}

/**
 * Get fully-resolved deployment settings for a chain.
 *
 * Reads `config/<network>.json5` (if present) and applies `DEFAULT_SETTINGS`
 * for any field the network omits. Pure / sync — safe to call from non-deploy
 * contexts (e.g. the status task). Returns full defaults for unknown chains.
 */
export function getResolvedSettings(chainId: number): ResolvedSettings {
  const file = loadConfigFile(chainId)
  return {
    rewardsManager: {
      revertOnIneligible: file.RewardsManager?.revertOnIneligible ?? DEFAULT_SETTINGS.rewardsManager.revertOnIneligible,
      eligibilityOracle: resolveEligibilityOracle(file.RewardsManager?.eligibilityOracle, 'RewardsManager', chainId),
    },
    recurringAgreementManager: {
      eligibilityOracle: resolveEligibilityOracle(
        file.RecurringAgreementManager?.eligibilityOracle,
        'RecurringAgreementManager',
        chainId,
      ),
    },
    issuanceAllocator: {
      issuancePerBlock: file.IssuanceAllocator?.issuancePerBlock,
      allocations: resolveAllocations(file.IssuanceAllocator?.allocations, chainId),
    },
    recurringCollector: {
      revokeSignerThawingPeriod:
        file.RecurringCollector?.revokeSignerThawingPeriod ??
        DEFAULT_SETTINGS.recurringCollector.revokeSignerThawingPeriod,
      eip712Name: file.RecurringCollector?.eip712Name ?? DEFAULT_SETTINGS.recurringCollector.eip712Name,
      eip712Version: file.RecurringCollector?.eip712Version ?? DEFAULT_SETTINGS.recurringCollector.eip712Version,
    },
    rewardsEligibilityOracle: {
      eligibilityPeriod:
        file.RewardsEligibilityOracle?.eligibilityPeriod !== undefined
          ? BigInt(file.RewardsEligibilityOracle.eligibilityPeriod)
          : DEFAULT_SETTINGS.rewardsEligibilityOracle.eligibilityPeriod,
      oracleUpdateTimeout:
        file.RewardsEligibilityOracle?.oracleUpdateTimeout !== undefined
          ? BigInt(file.RewardsEligibilityOracle.oracleUpdateTimeout)
          : DEFAULT_SETTINGS.rewardsEligibilityOracle.oracleUpdateTimeout,
    },
    subgraphService: {
      blockClosingAllocationWithActiveAgreement:
        file.SubgraphService?.blockClosingAllocationWithActiveAgreement ??
        DEFAULT_SETTINGS.subgraphService.blockClosingAllocationWithActiveAgreement,
    },
  }
}

/**
 * Convenience wrapper for deploy scripts that have an `env` but not a chainId.
 */
export async function getResolvedSettingsForEnv(env: Environment): Promise<ResolvedSettings> {
  const chainId = await getTargetChainIdFromEnv(env)
  return getResolvedSettings(chainId)
}

/** A target's allocation parsed to wei (GRT × 1e18). */
export interface ResolvedAllocation {
  target: AllocationTargetContractName
  allocatorMintingRate: bigint
  selfMintingRate: bigint
}

/**
 * Validate the issuance allocation table against RM's on-chain `issuancePerBlock`
 * and return the per-target rates parsed to wei.
 *
 * Errors (early, before any TX) when:
 *  - allocations are declared but `issuancePerBlock` is not (config must be self-describing),
 *  - the declared `issuancePerBlock` differs from RM's on-chain value (config never sets it), or
 *  - the allocations don't sum to exactly `issuancePerBlock`.
 *
 * Returns an empty list when no allocations are configured (nothing to do).
 */
export function validateIssuanceAllocations(
  settings: ResolvedSettings,
  rmIssuancePerBlock: bigint,
): ResolvedAllocation[] {
  const cfg = settings.issuanceAllocator
  if (cfg.allocations.length === 0) return []

  if (cfg.issuancePerBlock === undefined) {
    throw new Error(
      'IssuanceAllocator.allocations are configured but IssuanceAllocator.issuancePerBlock is not; ' +
        'declare the expected total so the table can be validated against it',
    )
  }
  const declared = parseUnits(cfg.issuancePerBlock, 18)
  if (declared !== rmIssuancePerBlock) {
    throw new Error(
      `IssuanceAllocator.issuancePerBlock (${cfg.issuancePerBlock}) does not match RM on-chain ` +
        `issuancePerBlock (${formatEther(rmIssuancePerBlock)} GRT); config does not set the rate — ` +
        `correct the config (or the on-chain rate via its own governance path)`,
    )
  }

  const allocations = cfg.allocations.map((a) => ({
    target: a.target,
    allocatorMintingRate: parseUnits(a.allocatorGrtPerBlock, 18),
    selfMintingRate: parseUnits(a.selfGrtPerBlock, 18),
  }))
  const sum = allocations.reduce((acc, a) => acc + a.allocatorMintingRate + a.selfMintingRate, 0n)
  if (sum !== declared) {
    throw new Error(
      `IssuanceAllocator.allocations sum to ${formatEther(sum)} GRT but issuancePerBlock is ` +
        `${cfg.issuancePerBlock} GRT; the table must allocate exactly the full issuance`,
    )
  }
  return allocations
}
