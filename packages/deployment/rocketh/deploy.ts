import type { DeploymentMetadata } from '@graphprotocol/toolshed/deployments'
import type { Environment } from '@rocketh/core/types'
import { deploy } from '@rocketh/deploy'
import { deployViaProxy } from '@rocketh/proxy'
import { execute, read, tx } from '@rocketh/read-execute'
import { createPublicClient, custom } from 'viem'

import type { AnyAddressBookOps } from '../lib/address-book-ops.js'
import {
  autoDetectForkNetwork,
  getAddressBookForType,
  getForkTargetChainId,
  getHorizonAddressBook,
  getIssuanceAddressBook,
  getSubgraphServiceAddressBook,
  getTargetChainIdFromEnv,
  isForkMode,
} from '../lib/address-book-utils.js'
import type { RegistryEntry } from '../lib/contract-registry.js'
import { accounts, data } from './config.js'

/**
 * Options for updating an address book after deployment
 */
export interface DeploymentUpdate {
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
  /** Proxy deployment metadata (for verification of the proxy contract itself) */
  proxyDeployment?: DeploymentMetadata
  /** Implementation deployment metadata (for verification of proxied contracts) */
  implementationDeployment?: DeploymentMetadata
  /** Deployment metadata (for verification of non-proxied contracts) */
  deployment?: DeploymentMetadata
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
   * Auto-detect fork network by querying anvil.
   * Call at the top of any task that needs fork awareness.
   * No-op if FORK_NETWORK is already set or node isn't an anvil fork.
   */
  autoDetect: () => autoDetectForkNetwork(),

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
   * Update horizon address book after deploying a contract.
   * Supports both standalone and proxied contracts.
   */
  updateHorizonAddressBook: async (env: Environment, update: DeploymentUpdate) => {
    const chainId = await getTargetChainIdFromEnv(env)
    await applyDeploymentUpdate(getHorizonAddressBook(chainId), update)
  },

  /**
   * Update subgraph-service address book after deploying a contract.
   * Supports both standalone and proxied contracts.
   */
  updateSubgraphServiceAddressBook: async (env: Environment, update: DeploymentUpdate) => {
    const chainId = await getTargetChainIdFromEnv(env)
    await applyDeploymentUpdate(getSubgraphServiceAddressBook(chainId), update)
  },

  /**
   * Update issuance address book after deploying a contract.
   * Call this after rocketh's deployViaProxy or deploy to sync the address book.
   */
  updateIssuanceAddressBook: async (env: Environment, update: DeploymentUpdate) => {
    const chainId = await getTargetChainIdFromEnv(env)
    await applyDeploymentUpdate(getIssuanceAddressBook(chainId), update)
  },

  /**
   * Update the address book for a contract, choosing the correct book from
   * `contract.addressBook`. Single dispatch point — adding a new address book
   * type will surface as a TypeScript error in `getAddressBookForType`.
   */
  updateAddressBookForContract: async (env: Environment, contract: RegistryEntry, update: DeploymentUpdate) => {
    const chainId = await getTargetChainIdFromEnv(env)
    await applyDeploymentUpdate(getAddressBookForType(contract.addressBook, chainId), update)
  },
}

function applyDeploymentUpdate(addressBook: AnyAddressBookOps, update: DeploymentUpdate): void {
  if (update.proxy) {
    addressBook.setProxy(update.name, update.address, update.implementation!, update.proxyAdmin!, update.proxy)
    if (update.proxyDeployment) {
      addressBook.setProxyDeploymentMetadata(update.name, update.proxyDeployment)
    }
    if (update.implementationDeployment) {
      addressBook.setImplementationDeploymentMetadata(update.name, update.implementationDeployment)
    }
  } else {
    addressBook.setContract(update.name, update.address)
    if (update.deployment) {
      addressBook.setDeploymentMetadata(update.name, update.deployment)
    }
  }
}

// Re-export rocketh functions for convenience
export { deploy, deployViaProxy, execute, read, tx }

// Re-export types and config
export type { Environment }
export { accounts, data }
