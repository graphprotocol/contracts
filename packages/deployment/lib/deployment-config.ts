import { readFileSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import type { Environment } from '@rocketh/core/types'

import { getTargetChainIdFromEnv } from './address-book-utils.js'

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
 * Every field is concrete — defaults from `DEFAULT_SETTINGS` are applied for
 * any field a network's config file omits. Consumers (deploy scripts and
 * status checks) read this directly without per-call `??` fallbacks, so the
 * "expected value" lives in exactly one place per field.
 */
export interface ResolvedSettings {
  rewardsManager: {
    /** Revert on reward claim attempts by ineligible indexers. */
    revertOnIneligible: boolean
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
  rewardsManager: {
    revertOnIneligible: true,
  },
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

/**
 * Strip single-line // comments from JSON5-style content so it can be parsed
 * by JSON.parse. Preserves strings containing //.
 */
function stripComments(text: string): string {
  return text.replace(/^\s*\/\/.*$/gm, '').replace(/,(\s*[}\]])/g, '$1')
}

function loadConfigFile(chainId: number): DeploymentConfigFile {
  const networkName = CHAIN_CONFIG_MAP[chainId]
  if (!networkName) return {}

  const configPath = resolve(__dirname, '..', 'config', `${networkName}.json5`)
  try {
    const raw = readFileSync(configPath, 'utf-8')
    return JSON.parse(stripComments(raw)) as DeploymentConfigFile
  } catch {
    return {}
  }
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
