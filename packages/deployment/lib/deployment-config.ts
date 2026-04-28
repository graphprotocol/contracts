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

export interface DeploymentConfig {
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
 * Strip single-line // comments from JSON5-style content so it can be parsed
 * by JSON.parse. Preserves strings containing //.
 */
function stripComments(text: string): string {
  return text.replace(/^\s*\/\/.*$/gm, '').replace(/,(\s*[}\]])/g, '$1')
}

/**
 * Load deployment configuration for a chain ID.
 *
 * Reads from packages/deployment/config/<network>.json5.
 * Returns empty config when the chain is unknown or the file is missing/invalid.
 * Silent — no logging — so it can be used from non-deploy contexts (e.g. status task).
 */
export function loadDeploymentConfigForChain(chainId: number): DeploymentConfig {
  const networkName = CHAIN_CONFIG_MAP[chainId]
  if (!networkName) return {}

  const configPath = resolve(__dirname, '..', 'config', `${networkName}.json5`)
  try {
    const raw = readFileSync(configPath, 'utf-8')
    return JSON.parse(stripComments(raw)) as DeploymentConfig
  } catch {
    return {}
  }
}

/**
 * Load deployment configuration for the target network.
 *
 * Reads from packages/deployment/config/<network>.json5.
 * Falls back to empty config if file not found (local/fork mode).
 */
export async function loadDeploymentConfig(env: Environment): Promise<DeploymentConfig> {
  const chainId = await getTargetChainIdFromEnv(env)
  const networkName = CHAIN_CONFIG_MAP[chainId]

  if (!networkName) {
    env.showMessage(`   No deployment config for chain ${chainId}, using defaults`)
    return {}
  }

  const config = loadDeploymentConfigForChain(chainId)
  if (Object.keys(config).length === 0) {
    env.showMessage(`   Config file not found or invalid: config/${networkName}.json5, using defaults`)
  } else {
    env.showMessage(`   Loaded config from config/${networkName}.json5`)
  }
  return config
}
