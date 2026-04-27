import type { Environment } from '@rocketh/core/types'
import { encodeFunctionData } from 'viem'

import { getTargetChainIdFromEnv } from './address-book-utils.js'
import type { AnyAddressBookOps } from './address-book-ops.js'
import { GRAPH_PROXY_ADMIN_ABI, OZ_PROXY_ADMIN_ABI } from './abis.js'
import { type AddressBookType, type ProxyType, type RegistryEntry } from './contract-registry.js'
import { getOnChainImplementation } from './deploy-implementation.js'
import { createGovernanceTxBuilder, saveGovernanceTx } from './execute-governance.js'
import { graph } from '../rocketh/deploy.js'
import type { TxBuilder, TxMetadata } from './tx-builder.js'

/**
 * Configuration for upgrading an implementation (manual override mode)
 * @deprecated Use registry-driven approach instead: upgradeImplementation(env, 'ContractName', overrides?)
 */
export interface ImplementationUpgradeConfig {
  /** Contract name (e.g., 'RewardsManager', 'SubgraphService') */
  contractName: string

  /**
   * Name of the proxy admin entry in address book.
   * Example: 'GraphProxyAdmin' for legacy GraphProxy contracts.
   *
   * Optional for OZ v5 TransparentUpgradeableProxy contracts (subgraph-service
   * and issuance) — the per-proxy admin address is read from the contract
   * entry's proxyAdmin field.
   */
  proxyAdminName?: string

  /**
   * Implementation contract name if different from contractName.
   * Used when a proxy is upgraded to a different contract type.
   *
   * Example: ReclaimedRewards proxy upgraded to DirectAllocation implementation
   *   contractName: 'ReclaimedRewards'
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
   * Example: ReclaimedRewards proxy upgraded to DirectAllocation implementation
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
 * await upgradeImplementation(env, Contracts.issuance.ReclaimedRewards, {
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
/**
 * Build upgrade TXs for a contract and add them to an existing builder.
 *
 * Checks the address book for a pendingImplementation. If found, encodes upgrade
 * TX(s) and adds them to the provided builder. Returns without exiting.
 *
 * Use this when building a batch of upgrades (e.g., GIP-level stage scripts).
 * For single-contract upgrades that save and exit, use `upgradeImplementation`.
 *
 * @returns Whether an upgrade was needed (pendingImplementation existed)
 */
export async function buildUpgradeTxs(
  env: Environment,
  entryOrConfig: RegistryEntry | ImplementationUpgradeConfig,
  builder: TxBuilder,
  overrides?: ImplementationUpgradeOverrides,
): Promise<{ upgraded: boolean }> {
  const config: ImplementationUpgradeConfig =
    'name' in entryOrConfig ? createUpgradeConfigFromRegistry(entryOrConfig, overrides) : entryOrConfig
  const { contractName, proxyAdminName, proxyType = 'graph', addressBook = 'horizon' } = config

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
    // No pending implementation stored — check if a shared implementation has changed on-chain
    const implName = config.implementationName
    if (implName && contractEntry?.address) {
      const implDepName = `${implName}_Implementation`
      const implDep = env.getOrNull(implDepName)
      if (implDep) {
        const client = graph.getPublicClient(env)
        const onChainImpl = await getOnChainImplementation(client, contractEntry.address, proxyType)
        if (onChainImpl.toLowerCase() !== implDep.address.toLowerCase()) {
          // Shared implementation changed — auto-set pendingImplementation
          const implMetadata = addressBookInstance.getDeploymentMetadata(implDepName)
          addressBookInstance.setPendingImplementationWithMetadata(
            contractName,
            implDep.address,
            implMetadata ?? { txHash: '', bytecodeHash: '' },
          )
          env.showMessage(`  ⚠️  ${contractName}: shared implementation changed, setting pending upgrade`)
          // Fall through to process the upgrade
        } else {
          env.showMessage(`  ✓ ${contractName}: no pending implementation`)
          return { upgraded: false }
        }
      } else {
        env.showMessage(`  ✓ ${contractName}: no pending implementation`)
        return { upgraded: false }
      }
    } else {
      env.showMessage(`  ✓ ${contractName}: no pending implementation`)
      return { upgraded: false }
    }
  }

  // Re-read entry after potential auto-set
  const updatedEntry = addressBookInstance.getEntry(contractName)
  if (!updatedEntry?.pendingImplementation?.address) {
    return { upgraded: false }
  }

  // Get proxy admin address
  let proxyAdminAddress: string | undefined
  if (updatedEntry.proxyAdmin) {
    proxyAdminAddress = updatedEntry.proxyAdmin
  } else if (proxyAdminName) {
    proxyAdminAddress = addressBookInstance.getEntry(proxyAdminName)?.address
  }

  if (!proxyAdminAddress) {
    throw new Error(
      `No proxy admin found for ${contractName}. ` +
        `Expected proxyAdmin field in address book entry or proxyAdminName in registry.`,
    )
  }

  const proxyAddress = updatedEntry.address
  const pendingImpl = updatedEntry.pendingImplementation!.address
  const currentImpl = updatedEntry.implementation ?? 'unknown'

  env.showMessage(`  + ${contractName}: ${pendingImpl.slice(0, 10)}... (${proxyType} proxy)`)

  if (proxyType === 'transparent') {
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
        args: { proxy: proxyAddress, implementation: pendingImpl, data: '0x [empty]' },
      },
      stateChanges: {
        [`${contractName} implementation`]: { current: currentImpl, new: pendingImpl },
      },
      notes: 'OZ TransparentUpgradeableProxy upgrade via per-proxy ProxyAdmin',
    }
    builder.addTx({ to: proxyAdminAddress, value: '0', data: upgradeData }, metadata)
  } else {
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

    builder.addTx(
      { to: proxyAdminAddress, value: '0', data: upgradeData },
      {
        toLabel: 'GraphProxyAdmin',
        contractName,
        decoded: {
          function: 'upgrade(address,address)',
          args: { proxy: proxyAddress, implementation: pendingImpl },
        },
        notes: 'Graph legacy proxy upgrade (step 1/2: set pending implementation)',
      },
    )
    builder.addTx(
      { to: proxyAdminAddress, value: '0', data: acceptData },
      {
        toLabel: 'GraphProxyAdmin',
        contractName,
        decoded: {
          function: 'acceptProxy(address,address)',
          args: { implementation: pendingImpl, proxy: proxyAddress },
        },
        stateChanges: {
          [`${contractName} implementation`]: { current: currentImpl, new: pendingImpl },
        },
        notes: 'Graph legacy proxy upgrade (step 2/2: accept and activate)',
      },
    )
  }

  return { upgraded: true }
}

/**
 * Upgrade an implementation via governance TX (registry-driven)
 *
 * Generates a governance TX batch file for a single contract upgrade, then exits.
 * For batch upgrades (multiple contracts in one TX batch), use `buildUpgradeTxs` instead.
 *
 * @example Registry-driven with Contracts object (recommended):
 * ```typescript
 * import { Contracts } from '../../lib/contract-registry.js'
 * await upgradeImplementation(env, Contracts.horizon.RewardsManager)
 * await upgradeImplementation(env, Contracts["subgraph-service"].SubgraphService)
 * await upgradeImplementation(env, Contracts.issuance.ReclaimedRewards, {
 *   implementationName: 'DirectAllocation', // Upgrade to different implementation
 * })
 * ```
 */
export async function upgradeImplementation(
  env: Environment,
  entryOrConfig: RegistryEntry | ImplementationUpgradeConfig,
  overrides?: ImplementationUpgradeOverrides,
): Promise<ImplementationUpgradeResult> {
  const config: ImplementationUpgradeConfig =
    'name' in entryOrConfig ? createUpgradeConfigFromRegistry(entryOrConfig, overrides) : entryOrConfig

  const builder = await createGovernanceTxBuilder(env, `upgrade-${config.contractName}`, {
    name: `${config.contractName} Upgrade`,
    description: `Upgrade ${config.contractName} proxy to new implementation`,
  })

  env.showMessage(`\n🔧 Upgrading ${config.contractName}...`)
  const { upgraded } = await buildUpgradeTxs(env, entryOrConfig, builder, overrides)

  if (!upgraded) {
    env.showMessage(`\n✓ No pending ${config.contractName} implementation to upgrade`)
    return { upgraded: false, executed: false }
  }

  saveGovernanceTx(env, builder, `${config.contractName} upgrade`)
  return { upgraded: true, executed: false }
}
