import type { DeploymentMetadata } from '@graphprotocol/toolshed/deployments'
import type { Environment } from '@rocketh/core/types'
import { deploy } from '@rocketh/deploy'
import { deployViaProxy } from '@rocketh/proxy'
import { execute, read, tx } from '@rocketh/read-execute'
import { createPublicClient, custom } from 'viem'

import {
  getForkTargetChainId,
  getHorizonAddressBook,
  getIssuanceAddressBook,
  getSubgraphServiceAddressBook,
  getTargetChainIdFromEnv,
  isForkMode,
} from '../lib/address-book-utils.js'
import { accounts, data } from './config.js'

/**
 * Options for updating issuance address book after deployment
 */
export interface IssuanceDeploymentUpdate {
  /** Contract name in the address book */
  name: string
  /** Deployed address (proxy address if proxied) */
  address: string
  /** For proxied contracts: proxy admin address */
  proxyAdmin?: string
  /** For proxied contracts: implementation address */
  implementation?: string
  /** Proxy type if this is a proxied contract */
  proxy?: 'transparent' | 'graph'
  /** Implementation deployment metadata (for verification) */
  implementationDeployment?: DeploymentMetadata
}

/**
 * Graph Protocol deployment helpers
 *
 * These helpers provide common functionality for deploy scripts:
 * - Address book access (fork-aware)
 * - Viem public client creation
 * - Chain ID utilities
 *
 * @example
 * ```typescript
 * import type { DeployScriptModule } from '@rocketh/core/types'
 * import { deploy } from '@rocketh/deploy'
 * import { graph } from '../../rocketh/deploy.js'
 *
 * const func: DeployScriptModule = async (env) => {
 *   const deployFn = deploy(env)
 *   const client = graph.getPublicClient(env)
 *   const addressBook = graph.getHorizonAddressBook()
 *   // ...
 * }
 * ```
 */
export const graph = {
  /**
   * Get a viem public client for on-chain queries
   */
  getPublicClient: (env: Environment) =>
    createPublicClient({
      transport: custom(env.network.provider),
    }),

  /**
   * Get fork target chain ID (null if not in fork mode).
   * Maps FORK_NETWORK env var to actual chain ID.
   */
  getForkTargetChainId: () => getForkTargetChainId(),

  /**
   * Check if running in fork mode
   */
  isForkMode: () => isForkMode(),

  /**
   * Get the Horizon address book (fork-aware)
   */
  getHorizonAddressBook: (chainId?: number) => getHorizonAddressBook(chainId),

  /**
   * Get the SubgraphService address book (fork-aware)
   */
  getSubgraphServiceAddressBook: (chainId?: number) => getSubgraphServiceAddressBook(chainId),

  /**
   * Get the Issuance address book (fork-aware)
   */
  getIssuanceAddressBook: (chainId?: number) => getIssuanceAddressBook(chainId),

  /**
   * Update issuance address book after deploying a contract.
   * Call this after rocketh's deployViaProxy or deploy to sync the address book.
   *
   * @param env - Rocketh environment (used to get chain ID from provider)
   * @param update - Deployment update details
   */
  updateIssuanceAddressBook: async (env: Environment, update: IssuanceDeploymentUpdate) => {
    const chainId = await getTargetChainIdFromEnv(env)
    const addressBook = getIssuanceAddressBook(chainId)

    if (update.proxy) {
      addressBook.setProxy(
        update.name as Parameters<typeof addressBook.setProxy>[0],
        update.address,
        update.implementation!,
        update.proxyAdmin!,
        update.proxy,
      )
      // Store implementation deployment metadata for verification
      if (update.implementationDeployment) {
        addressBook.setImplementationDeploymentMetadata(
          update.name as Parameters<typeof addressBook.setImplementationDeploymentMetadata>[0],
          update.implementationDeployment,
        )
      }
    } else {
      addressBook.setContract(update.name as Parameters<typeof addressBook.setContract>[0], update.address)
    }
  },
}

// Re-export rocketh functions for convenience
export { deploy, deployViaProxy, execute, read, tx }

// Re-export types and config
export type { Environment }
export { accounts, data }
