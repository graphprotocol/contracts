import { readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

import type { Environment } from '@rocketh/core/types'
import JSON5 from 'json5'

import { getTargetChainIdFromEnv } from './address-book-utils.js'
import { ELIGIBILITY_ORACLE_CONTRACTS, type EligibilityOracleContractName } from './contract-registry.js'

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
    ramAllocatorMintingGrtPerBlock?: string
    ramSelfMintingGrtPerBlock?: string
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
    /** GRT/block minted by IA and routed to RAM. `'0'` means unconfigured (skip allocation). */
    ramAllocatorMintingGrtPerBlock: string
    /** GRT/block self-minted by RAM. `'0'` means RAM does not self-mint. */
    ramSelfMintingGrtPerBlock: string
  }
  recurringCollector: {
    /** Signer revocation thaw period in seconds (constructor arg). */
    revokeSignerThawingPeriod: string
    /** EIP-712 domain name (init arg). */
    eip712Name: string
    /** EIP-712 domain version (init arg). */
    eip712Version: string
  }
}

const DEFAULT_SETTINGS: ResolvedSettings = {
  // eligibilityOracle has no default — omission means "no oracle" (see below).
  rewardsManager: {
    revertOnIneligible: true,
  },
  recurringAgreementManager: {},
  issuanceAllocator: {
    ramAllocatorMintingGrtPerBlock: '0',
    ramSelfMintingGrtPerBlock: '0',
  },
  recurringCollector: {
    revokeSignerThawingPeriod: '28800', // ~1 day at 3s blocks
    eip712Name: 'RecurringCollector',
    eip712Version: '1',
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
      ramAllocatorMintingGrtPerBlock:
        file.IssuanceAllocator?.ramAllocatorMintingGrtPerBlock ??
        DEFAULT_SETTINGS.issuanceAllocator.ramAllocatorMintingGrtPerBlock,
      ramSelfMintingGrtPerBlock:
        file.IssuanceAllocator?.ramSelfMintingGrtPerBlock ??
        DEFAULT_SETTINGS.issuanceAllocator.ramSelfMintingGrtPerBlock,
    },
    recurringCollector: {
      revokeSignerThawingPeriod:
        file.RecurringCollector?.revokeSignerThawingPeriod ??
        DEFAULT_SETTINGS.recurringCollector.revokeSignerThawingPeriod,
      eip712Name: file.RecurringCollector?.eip712Name ?? DEFAULT_SETTINGS.recurringCollector.eip712Name,
      eip712Version: file.RecurringCollector?.eip712Version ?? DEFAULT_SETTINGS.recurringCollector.eip712Version,
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
