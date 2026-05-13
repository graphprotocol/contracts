import type { Artifact, Environment } from '@rocketh/core/types'
import { encodeAbiParameters, getAddress } from 'viem'

import { getAddressBookForType, getTargetChainIdFromEnv } from './address-book-utils.js'
import {
  getLibraryResolver,
  linkArtifactLibraries,
  loadContractsArtifact,
  loadHorizonBuildArtifact,
  loadIssuanceArtifact,
  loadOpenZeppelinArtifact,
  loadSubgraphServiceArtifact,
} from './artifact-loaders.js'
import { computeBytecodeHash } from './bytecode-utils.js'
import { getContractMetadata, type AddressBookType, type ArtifactSource, type ProxyType } from './contract-registry.js'
import { buildDeploymentMetadata } from './deployment-metadata.js'
import { deploy, graph } from '../rocketh/deploy.js'

// Re-export artifact loaders for backwards compatibility
export { loadContractsArtifact, loadIssuanceArtifact, loadSubgraphServiceArtifact }

// Re-export ArtifactSource for backwards compatibility
export type { ArtifactSource }

// ERC1967 implementation storage slot (for OZ TransparentUpgradeableProxy)
const ERC1967_IMPLEMENTATION_SLOT = '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc' as const

/**
 * Read the current implementation address for a proxy contract.
 *
 * @param client - Viem public client
 * @param proxyAddress - Address of the proxy contract
 * @param proxyType - 'graph' for Graph legacy proxy, 'transparent' for OZ TransparentProxy
 * @param proxyAdminAddress - Address of the proxy admin (required for graph type)
 */
export async function getOnChainImplementation(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  client: any,
  proxyAddress: string,
  proxyType: 'graph' | 'transparent',
  proxyAdminAddress?: string,
): Promise<string> {
  if (proxyType === 'transparent') {
    const implSlotValue = await client.getStorageAt({
      address: proxyAddress as `0x${string}`,
      slot: ERC1967_IMPLEMENTATION_SLOT,
    })
    return getAddress('0x' + (implSlotValue?.slice(26) ?? ''))
  } else {
    const data = await client.readContract({
      address: proxyAdminAddress as `0x${string}`,
      abi: [
        {
          name: 'getProxyImplementation',
          type: 'function',
          inputs: [{ name: '_proxy', type: 'address' }],
          outputs: [{ name: '', type: 'address' }],
          stateMutability: 'view',
        },
      ],
      functionName: 'getProxyImplementation',
      args: [proxyAddress as `0x${string}`],
    })
    return data as string
  }
}

/**
 * Configuration for deploying an upgradeable implementation
 */
export interface ImplementationDeployConfig {
  /** Contract name (e.g., 'RewardsManager', 'SubgraphService') */
  contractName: string

  /**
   * Artifact source configuration
   *
   * For @graphprotocol/contracts:
   *   { type: 'contracts', path: 'rewards', name: 'RewardsManager' }
   *
   * For @graphprotocol/subgraph-service (Foundry format):
   *   { type: 'subgraph-service', name: 'SubgraphService' }
   *
   * For @graphprotocol/issuance:
   *   { type: 'issuance', path: 'contracts/allocate/DirectAllocation.sol/DirectAllocation' }
   *
   * Legacy shorthand (contracts only):
   *   artifactPath: 'rewards' + artifactName defaults to contractName
   */
  artifact?: ArtifactSource

  /** @deprecated Use artifact.path instead */
  artifactPath?: string

  /**
   * Proxy type
   * - 'graph': Graph Protocol's custom proxy (upgrade + acceptProxy)
   * - 'transparent': OpenZeppelin TransparentUpgradeableProxy (upgradeAndCall)
   *
   * Default: 'graph'
   */
  proxyType?: ProxyType

  /**
   * Name of the proxy admin deployment record.
   * e.g., 'GraphProxyAdmin' for legacy GraphProxy contracts.
   *
   * Optional: If omitted, defaults to `${contractName}_ProxyAdmin`.
   * Per-proxy admins (OZ v5 TransparentUpgradeableProxy contracts) follow this
   * default and store the admin address inline in their address book entry.
   */
  proxyAdminName?: string

  /**
   * Address book to store pending implementation
   * Default: 'horizon'
   */
  addressBook?: AddressBookType

  /** Constructor arguments (default: []) */
  constructorArgs?: unknown[]
}

/**
 * Result of implementation deployment
 */
export interface ImplementationDeployResult {
  /** Whether a new implementation was deployed */
  deployed: boolean

  /** Address of the implementation (new or existing) */
  address: string

  /** Whether the bytecode changed (deployment was needed) */
  bytecodeChanged: boolean

  /** Transaction hash if newly deployed */
  txHash?: string
}

/**
 * Load artifact based on source configuration. Throws if the artifact can't be loaded.
 */
export function loadArtifactFromSource(source: ArtifactSource): Artifact {
  switch (source.type) {
    case 'contracts':
      return loadContractsArtifact(source.path, source.name)
    case 'subgraph-service':
      return loadSubgraphServiceArtifact(source.name)
    case 'horizon':
      return loadHorizonBuildArtifact(source.path)
    case 'issuance':
      return loadIssuanceArtifact(source.path)
    case 'openzeppelin':
      return loadOpenZeppelinArtifact(source.name)
  }
}

/**
 * Like {@link loadArtifactFromSource}, but returns `undefined` instead of throwing.
 * Intended for sync-style flows where a missing artifact shouldn't abort the pass.
 */
export function tryLoadArtifactFromSource(source: ArtifactSource | undefined): Artifact | undefined {
  if (!source) return undefined
  try {
    return loadArtifactFromSource(source)
  } catch {
    return undefined
  }
}

/**
 * Compute the bytecode hash for an artifact source, with library resolution.
 *
 * This is the canonical bytecodeHash recorded in address-book deployment metadata —
 * deploy-time, sync backfill, and `checkShouldSync` all agree on this fingerprint.
 *
 * Use this instead of calling `computeBytecodeHash` directly on rocketh's linked
 * `deployedBytecode`: linked bytecode has real library addresses substituted in,
 * so its hash diverges from the placeholder-fingerprint hash this helper produces
 * for any library-using contract.
 *
 * Throws if the artifact cannot be loaded.
 */
export function computeArtifactBytecodeHash(source: ArtifactSource): string {
  const artifact = loadArtifactFromSource(source)
  return computeBytecodeHash(
    artifact.deployedBytecode ?? '0x',
    artifact.deployedLinkReferences,
    getLibraryResolver(source.type),
  )
}

/**
 * Like {@link computeArtifactBytecodeHash}, but returns `undefined` instead of
 * throwing if the artifact can't be loaded. Intended for sync-style flows where
 * a missing artifact shouldn't abort the whole pass.
 */
export function tryComputeArtifactBytecodeHash(source: ArtifactSource | undefined): string | undefined {
  if (!source) return undefined
  try {
    return computeArtifactBytecodeHash(source)
  } catch {
    return undefined
  }
}

/**
 * Build ImplementationDeployConfig from registry metadata
 *
 * This helper reduces boilerplate in deploy scripts by using the centralized
 * contract registry for artifact paths, proxy patterns, and address books.
 *
 * @param addressBook - Which address book the contract belongs to
 * @param contractName - The contract name (key in CONTRACT_REGISTRY[addressBook])
 * @param overrides - Optional overrides (e.g., constructorArgs)
 * @returns Configuration ready for deployImplementation()
 *
 * @example
 * ```typescript
 * // Simple usage - all config from registry
 * await deployImplementation(env, getImplementationConfig('horizon', 'RewardsManager'))
 *
 * // With constructor args
 * await deployImplementation(env, getImplementationConfig('subgraph-service', 'SubgraphService', {
 *   constructorArgs: [controller, disputeManager, tallyCollector, curation],
 * }))
 * ```
 */
export function getImplementationConfig(
  addressBook: AddressBookType,
  contractName: string,
  overrides?: Partial<Omit<ImplementationDeployConfig, 'contractName'>>,
): ImplementationDeployConfig {
  const metadata = getContractMetadata(addressBook, contractName)
  if (!metadata) {
    throw new Error(`Contract '${contractName}' not found in ${addressBook} registry`)
  }

  return {
    contractName,
    artifact: metadata.artifact,
    proxyType: metadata.proxyType,
    proxyAdminName: metadata.proxyAdminName, // undefined if not in registry (will auto-generate)
    addressBook,
    ...overrides,
  }
}

/**
 * Check if a contract has implementation deployment config in the registry
 */
export function hasImplementationConfig(addressBook: AddressBookType, contractName: string): boolean {
  const metadata = getContractMetadata(addressBook, contractName)
  return !!metadata?.artifact
}

/**
 * Deploy an upgradeable contract implementation with bytecode change detection
 *
 * This function handles the common pattern for deploying Graph Protocol
 * upgradeable implementations:
 *
 * 1. Verify prerequisites (proxy and admin exist from sync)
 * 2. Compare artifact bytecode with on-chain (accounting for metadata/immutables)
 * 3. Deploy new implementation if bytecode changed
 * 4. Store as pendingImplementation in address book for governance upgrade
 *
 * @example Graph Legacy (RewardsManager, Staking, Curation):
 * ```typescript
 * await deployImplementation(env, {
 *   contractName: 'RewardsManager',
 *   artifactPath: 'rewards',
 *   proxyAdminName: 'GraphProxyAdmin',
 * })
 * ```
 *
 * @example OZ Transparent (SubgraphService):
 * ```typescript
 * await deployImplementation(env, {
 *   contractName: 'SubgraphService',
 *   artifact: { type: 'subgraph-service', name: 'SubgraphService' },
 *   proxyType: 'transparent',
 *   proxyAdminName: 'SubgraphService_ProxyAdmin',
 *   addressBook: 'subgraph-service',
 *   constructorArgs: [controller, disputeManager, tallyCollector, curation],
 * })
 * ```
 */
export async function deployImplementation(
  env: Environment,
  config: ImplementationDeployConfig,
  libraries?: Record<string, string>,
): Promise<ImplementationDeployResult> {
  const { contractName, proxyAdminName, constructorArgs = [], proxyType = 'graph', addressBook = 'horizon' } = config

  // Resolve artifact source (support legacy artifactPath for backwards compatibility)
  const artifactSource: ArtifactSource = config.artifact ?? {
    type: 'contracts',
    path: config.artifactPath!,
    name: contractName,
  }

  const deployFn = deploy(env)

  // Get deployer account
  const deployer = env.namedAccounts.deployer
  if (!deployer) {
    throw new Error('No deployer account configured')
  }

  // Create viem client for on-chain queries
  const client = graph.getPublicClient(env)

  // 1) Verify imports completed (sync step must have run)
  const proxy = env.getOrNull(contractName)
  if (!proxy) {
    throw new Error(`${contractName} not imported. Run sync step first.`)
  }

  // Auto-generate proxy admin deployment record name if not provided
  const proxyAdminDeploymentName = proxyAdminName ?? `${contractName}_ProxyAdmin`
  const proxyAdmin = env.getOrNull(proxyAdminDeploymentName)
  if (!proxyAdmin) {
    throw new Error(`${proxyAdminDeploymentName} not imported. Run sync step first.`)
  }

  // 2) Load artifact (pre-link libraries so rocketh stores linked bytecode)
  const rawArtifact = loadArtifactFromSource(artifactSource)
  const artifact = libraries
    ? linkArtifactLibraries(rawArtifact, libraries as Record<string, `0x${string}`>)
    : rawArtifact
  const implDeploymentName = `${contractName}_Implementation`

  // Get address book to check pending implementation
  const targetChainId = await getTargetChainIdFromEnv(env)
  const addressBookInstance = getAddressBookForType(addressBook, targetChainId)

  // Compute local artifact bytecode hash (for storing with deployment)
  const localBytecodeHash = computeArtifactBytecodeHash(artifactSource)

  // 3) Pre-check: skip deployment if bytecodeHash and constructor args match
  // Rocketh's comparison can false-positive when sync creates bare records (e.g., wrong
  // argsData, unlinked library bytecodes). The content-aware bytecodeHash handles both
  // cases — it strips CBOR metadata and resolves library references by content hash.
  const contractEntry = addressBookInstance.entryExists(contractName)
    ? addressBookInstance.getEntry(contractName)
    : null
  const pendingImpl = contractEntry?.pendingImplementation
  const storedMetadata = pendingImpl?.deployment ?? addressBookInstance.getDeploymentMetadata(contractName)

  if (storedMetadata?.bytecodeHash && storedMetadata.bytecodeHash === localBytecodeHash) {
    // Bytecode matches — also verify constructor args (immutable values)
    let argsMatch = !storedMetadata.argsData // no stored args = can't compare, assume match
    if (storedMetadata.argsData) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const constructorDef = (artifact.abi as any[])?.find((item: any) => item.type === 'constructor')
      const localArgsData =
        constructorDef?.inputs?.length && constructorArgs.length
          ? encodeAbiParameters(constructorDef.inputs, constructorArgs as readonly unknown[])
          : '0x'
      argsMatch = localArgsData === storedMetadata.argsData
    }

    if (argsMatch) {
      const existingAddress = pendingImpl?.address ?? contractEntry?.implementation
      if (existingAddress) {
        env.showMessage(`\n✓ ${contractName} implementation unchanged`)
        return {
          deployed: false,
          address: existingAddress,
          bytecodeChanged: false,
        }
      }
    }
  }

  // 4) Deploy implementation - let rocketh decide based on its own records
  // Sync handles pending: if pending hash matches local, rocketh has bytecode to compare
  // If pending hash differs, sync skipped bytecode so rocketh will deploy fresh
  // Libraries are pre-linked into the artifact (step 2) so rocketh stores linked
  // bytecode — its CBOR-stripping comparison then matches on subsequent runs.
  const impl = await deployFn(implDeploymentName, { account: deployer, artifact, args: constructorArgs })

  if (!impl.newlyDeployed) {
    env.showMessage(`\n✓ ${contractName} implementation unchanged`)
    return {
      deployed: false,
      address: impl.address,
      bytecodeChanged: false,
    }
  }

  // 4) Get current on-chain implementation
  const currentOnChainImpl = await getOnChainImplementation(client, proxy.address, proxyType, proxyAdmin.address)

  env.showMessage(`\n📋 New ${contractName} implementation deployed: ${impl.address}`)
  env.showMessage(`   Current on-chain implementation: ${currentOnChainImpl}`)
  env.showMessage(`   Storing as pending implementation...`)

  // 5) Store as pending implementation in address book with full deployment metadata
  // (addressBookInstance already obtained above for bytecode hash check)

  // Get block info for timestamp
  let blockNumber: number | undefined
  let timestamp: string | undefined
  if (impl.transaction?.hash) {
    try {
      const receipt = await client.getTransactionReceipt({ hash: impl.transaction.hash as `0x${string}` })
      if (receipt?.blockNumber) {
        blockNumber = Number(receipt.blockNumber)
        const block = await client.getBlock({ blockNumber: receipt.blockNumber })
        if (block?.timestamp) {
          timestamp = new Date(Number(block.timestamp) * 1000).toISOString()
        }
      }
    } catch {
      // Block info lookup failed - not critical
    }
  }

  // Store with full deployment metadata for verification and reconstruction
  const metadata = buildDeploymentMetadata(impl, localBytecodeHash, { blockNumber, timestamp })
  if (metadata) {
    addressBookInstance.setPendingImplementationWithMetadata(contractName, impl.address, metadata)
  }

  env.showMessage(`✓ Pending implementation stored with deployment metadata.`)
  env.showMessage(`  Run upgrade task to generate TX and execute.`)

  return {
    deployed: true,
    address: impl.address,
    bytecodeChanged: true,
    txHash: impl.transaction?.hash,
  }
}
