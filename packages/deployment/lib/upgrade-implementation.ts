import type { Environment } from '@rocketh/core/types'
import { encodeFunctionData } from 'viem'

import { getTargetChainIdFromEnv } from './address-book-utils.js'
import type { AnyAddressBookOps } from './address-book-ops.js'
import { GRAPH_PROXY_ADMIN_ABI, OZ_PROXY_ADMIN_ABI } from './abis.js'
import { type AddressBookType, type ProxyType, type RegistryEntry } from './contract-registry.js'
import { createGovernanceTxBuilder } from './execute-governance.js'
import { graph } from '../rocketh/deploy.js'
import type { TxMetadata } from './tx-builder.js'

/**
 * Configuration for upgrading an implementation (manual override mode)
 * @deprecated Use registry-driven approach instead: upgradeImplementation(env, 'ContractName', overrides?)
 */
export interface ImplementationUpgradeConfig {
  /** Contract name (e.g., 'RewardsManager', 'SubgraphService') */
  contractName: string

  /**
   * Name of the proxy admin entry in address book.
   * Examples: 'GraphProxyAdmin', 'GraphIssuanceProxyAdmin'
   *
   * Optional for subgraph-service contracts - the proxy admin address
   * is read from the contract entry's proxyAdmin field.
   */
  proxyAdminName?: string

  /**
   * Implementation contract name if different from contractName.
   * Used when a proxy is upgraded to a different contract type.
   *
   * Example: PilotAllocation proxy upgraded to DirectAllocation implementation
   *   contractName: 'PilotAllocation'
   *   implementationName: 'DirectAllocation'
   *
   * Default: same as contractName
   */
  implementationName?: string

  /**
   * Proxy type
   * - 'graph': Graph Protocol's custom proxy (upgrade + acceptProxy)
   * - 'transparent': OpenZeppelin TransparentUpgradeableProxy (upgradeAndCall)
   *
   * Default: 'graph'
   */
  proxyType?: ProxyType

  /**
   * Address book to use
   * Default: 'horizon'
   */
  addressBook?: AddressBookType
}

/**
 * Optional overrides for registry-driven upgrade
 */
export interface ImplementationUpgradeOverrides {
  /**
   * Implementation contract name if different from contractName.
   * Used when a proxy is upgraded to a different contract type.
   *
   * Example: PilotAllocation proxy upgraded to DirectAllocation implementation
   */
  implementationName?: string

  /**
   * Override proxy admin name from registry
   */
  proxyAdminName?: string
}

/**
 * Result of implementation upgrade
 */
export interface ImplementationUpgradeResult {
  /** Whether upgrade was needed */
  upgraded: boolean

  /** Path to the generated TX batch file */
  txFile?: string

  /** Whether TX was executed (fork mode only) */
  executed: boolean
}

/**
 * Create upgrade config from registry entry
 */
function createUpgradeConfigFromRegistry(
  entry: RegistryEntry,
  overrides?: ImplementationUpgradeOverrides,
): ImplementationUpgradeConfig {
  return {
    contractName: entry.name,
    proxyAdminName: overrides?.proxyAdminName ?? entry.proxyAdminName,
    implementationName: overrides?.implementationName,
    proxyType: entry.proxyType,
    addressBook: entry.addressBook,
  }
}

/**
 * Upgrade an implementation via governance TX (registry-driven)
 *
 * @example Registry-driven with Contracts object (recommended):
 * ```typescript
 * import { Contracts } from '../../lib/contract-registry.js'
 * await upgradeImplementation(env, Contracts.horizon.RewardsManager)
 * await upgradeImplementation(env, Contracts["subgraph-service"].SubgraphService)
 * await upgradeImplementation(env, Contracts.issuance.PilotAllocation, {
 *   implementationName: 'DirectAllocation', // Upgrade to different implementation
 * })
 * ```
 *
 * @example Config-based (legacy):
 * ```typescript
 * await upgradeImplementation(env, {
 *   contractName: 'SubgraphService',
 *   proxyType: 'transparent',
 *   addressBook: 'subgraph-service',
 * })
 * ```
 */
export async function upgradeImplementation(
  env: Environment,
  entryOrConfig: RegistryEntry | ImplementationUpgradeConfig,
  overrides?: ImplementationUpgradeOverrides,
): Promise<ImplementationUpgradeResult> {
  // Handle overloads - convert registry entry to config
  const config: ImplementationUpgradeConfig =
    'name' in entryOrConfig ? createUpgradeConfigFromRegistry(entryOrConfig, overrides) : entryOrConfig
  const { contractName, proxyAdminName, proxyType = 'graph', addressBook = 'horizon' } = config

  // Use fork-local address book in fork mode, canonical address book otherwise
  const targetChainId = await getTargetChainIdFromEnv(env)
  const addressBookInstance: AnyAddressBookOps =
    addressBook === 'subgraph-service'
      ? graph.getSubgraphServiceAddressBook(targetChainId)
      : addressBook === 'issuance'
        ? graph.getIssuanceAddressBook(targetChainId)
        : graph.getHorizonAddressBook(targetChainId)

  // Check for pending implementation
  const contractEntry = addressBookInstance.getEntry(contractName)
  if (!contractEntry?.pendingImplementation?.address) {
    env.showMessage(`\n✓ No pending ${contractName} implementation to upgrade`)
    return { upgraded: false, executed: false }
  }

  // Get proxy admin address
  // Priority: 1) Per-proxy ProxyAdmin in entry (OZ v5 / subgraph-service)
  //           2) Shared ProxyAdmin by name (legacy horizon pattern)
  let proxyAdminAddress: string | undefined
  if (contractEntry.proxyAdmin) {
    // Per-proxy ProxyAdmin stored inline (OZ v5 issuance, subgraph-service)
    proxyAdminAddress = contractEntry.proxyAdmin
  } else if (proxyAdminName) {
    // Shared ProxyAdmin by name (horizon legacy pattern)
    proxyAdminAddress = addressBookInstance.getEntry(proxyAdminName)?.address
  }

  if (!proxyAdminAddress) {
    throw new Error(
      `No proxy admin found for ${contractName}. ` +
        `Expected proxyAdmin field in address book entry or proxyAdminName in registry.`,
    )
  }

  const proxyAddress = contractEntry.address
  const pendingImpl = contractEntry.pendingImplementation.address

  env.showMessage(`\n🔧 Upgrading ${contractName}...`)
  env.showMessage(`   Proxy: ${proxyAddress}`)
  env.showMessage(`   ProxyAdmin: ${proxyAdminAddress}`)
  env.showMessage(`   New implementation: ${pendingImpl}`)

  // Generate governance TX with deterministic name (overwrites if exists)
  const builder = await createGovernanceTxBuilder(env, `upgrade-${contractName}`, {
    name: `${contractName} Upgrade`,
    description: `Upgrade ${contractName} proxy to new implementation`,
  })

  // Get current implementation for state change tracking
  const currentImpl = contractEntry.implementation ?? 'unknown'

  // Build TX based on proxy type
  if (proxyType === 'transparent') {
    // OpenZeppelin v5 ProxyAdmin uses upgradeAndCall() with empty calldata
    // Note: we use empty bytes (0x) because not all contracts implement ERC165,
    // so supportsInterface cannot be used as a universal no-op
    const upgradeData = encodeFunctionData({
      abi: OZ_PROXY_ADMIN_ABI,
      functionName: 'upgradeAndCall',
      args: [proxyAddress as `0x${string}`, pendingImpl as `0x${string}`, '0x'],
    })

    const metadata: TxMetadata = {
      toLabel: `${contractName}_ProxyAdmin`,
      contractName,
      decoded: {
        function: 'upgradeAndCall(address,address,bytes)',
        args: {
          proxy: proxyAddress,
          implementation: pendingImpl,
          data: '0x [empty]',
        },
      },
      stateChanges: {
        [`${contractName} implementation`]: {
          current: currentImpl,
          new: pendingImpl,
        },
      },
      notes: 'OZ TransparentUpgradeableProxy upgrade via per-proxy ProxyAdmin',
    }
    builder.addTx({ to: proxyAdminAddress, value: '0', data: upgradeData }, metadata)
  } else {
    // Graph legacy: upgrade() + acceptProxy(implementation, proxy)
    // Note: GraphProxyAdmin.sol requires both implementation and proxy parameters,
    // despite IGraphProxyAdmin interface only showing proxy parameter (interface is outdated)
    const upgradeData = encodeFunctionData({
      abi: GRAPH_PROXY_ADMIN_ABI,
      functionName: 'upgrade',
      args: [proxyAddress as `0x${string}`, pendingImpl as `0x${string}`],
    })
    const acceptData = encodeFunctionData({
      abi: GRAPH_PROXY_ADMIN_ABI,
      functionName: 'acceptProxy',
      args: [pendingImpl as `0x${string}`, proxyAddress as `0x${string}`],
    })

    const upgradeMetadata: TxMetadata = {
      toLabel: 'GraphProxyAdmin',
      contractName,
      decoded: {
        function: 'upgrade(address,address)',
        args: {
          proxy: proxyAddress,
          implementation: pendingImpl,
        },
      },
      notes: 'Graph legacy proxy upgrade (step 1/2: set pending implementation)',
    }
    builder.addTx({ to: proxyAdminAddress, value: '0', data: upgradeData }, upgradeMetadata)

    const acceptMetadata: TxMetadata = {
      toLabel: 'GraphProxyAdmin',
      contractName,
      decoded: {
        function: 'acceptProxy(address,address)',
        args: {
          implementation: pendingImpl,
          proxy: proxyAddress,
        },
      },
      stateChanges: {
        [`${contractName} implementation`]: {
          current: currentImpl,
          new: pendingImpl,
        },
      },
      notes: 'Graph legacy proxy upgrade (step 2/2: accept and activate)',
    }
    builder.addTx({ to: proxyAdminAddress, value: '0', data: acceptData }, acceptMetadata)
  }

  const txFile = builder.saveToFile()
  env.showMessage(`   ✓ Governance TX saved: ${txFile}`)
  env.showMessage(`   Run: npx hardhat deploy:execute-governance --network ${env.name}`)

  // Exit to prevent subsequent deployment steps until governance TX is executed
  process.exit(1)
}
