import type { Artifact, Environment } from '@rocketh/core/types'
import type { DeploymentMetadata } from '@graphprotocol/toolshed/deployments'

import {
  loadContractsArtifact,
  loadIssuanceArtifact,
  loadOpenZeppelinArtifact,
  loadSubgraphServiceArtifact,
} from './artifact-loaders.js'
import { computeBytecodeHash } from './bytecode-utils.js'
import {
  type AddressBookType,
  type ArtifactSource,
  type ContractMetadata,
  getAddressBookEntryName,
  getContractMetadata,
} from './contract-registry.js'
import { getOnChainImplementation } from './deploy-implementation.js'
import { graph } from '../rocketh/deploy.js'
import type { AnyAddressBookOps } from './address-book-ops.js'

/**
 * Format an address based on SHOW_ADDRESSES environment variable
 * - 0: return empty string (no addresses shown)
 * - 1: return truncated address (0x1234567890...)
 * - 2 (default): return full address
 */
function formatAddress(address: string): string {
  const showAddresses = process.env.SHOW_ADDRESSES ?? '1'

  if (showAddresses === '0') {
    return ''
  } else if (showAddresses === '1') {
    return address.slice(0, 10) + '...'
  } else {
    // Default to full address (showAddresses === '2' or any other value)
    return address
  }
}

/**
 * Load artifact from any supported source type
 */
function loadArtifactFromSource(source: ArtifactSource): Artifact | undefined {
  try {
    switch (source.type) {
      case 'contracts':
        return loadContractsArtifact(source.path, source.name)
      case 'subgraph-service':
        return loadSubgraphServiceArtifact(source.name)
      case 'issuance':
        return loadIssuanceArtifact(source.path)
      case 'openzeppelin':
        return loadOpenZeppelinArtifact(source.name)
    }
  } catch {
    return undefined
  }
}

// ============================================================================
// Sync Change Detection & Record Reconstruction
// ============================================================================

/**
 * Result of checking whether a contract needs to be synced
 */
export interface SyncCheckResult {
  /** Whether sync should proceed */
  shouldSync: boolean
  /** Reason for the decision */
  reason: string
  /** Warning to display (e.g., bytecode changed) */
  warning?: string
}

/**
 * Check whether a contract needs to be synced
 *
 * Uses deployment metadata to determine if:
 * - Contract is new (no existing record) → sync
 * - Address changed → sync
 * - Local bytecode changed since deployment → warn, don't overwrite
 * - No changes → skip sync
 *
 * @param addressBook - Address book ops instance
 * @param contractName - Name of the contract
 * @param newAddress - Address to sync to
 * @param artifact - Artifact for bytecode comparison
 */
export function checkShouldSync(
  addressBook: AnyAddressBookOps,
  contractName: string,
  newAddress: string,
  artifact?: ArtifactSource,
): SyncCheckResult {
  // No existing entry - must sync
  if (!addressBook.entryExists(contractName)) {
    return { shouldSync: true, reason: 'new contract' }
  }

  const entry = addressBook.getEntry(contractName)

  // Address changed - must sync
  if (entry.address.toLowerCase() !== newAddress.toLowerCase()) {
    return { shouldSync: true, reason: 'address changed' }
  }

  // Check bytecode hash if deployment metadata exists
  const metadata = addressBook.getDeploymentMetadata(contractName)
  if (metadata?.bytecodeHash && artifact) {
    const loadedArtifact = loadArtifactFromSource(artifact)
    if (loadedArtifact?.deployedBytecode) {
      const localHash = computeBytecodeHash(loadedArtifact.deployedBytecode)
      if (metadata.bytecodeHash !== localHash) {
        return {
          shouldSync: false,
          reason: 'local bytecode changed since deployment',
          warning: `${contractName}: local bytecode differs from deployed (hash mismatch)`,
        }
      }
    }
  }

  // No changes detected - skip sync but still valid
  return { shouldSync: false, reason: 'unchanged' }
}

/**
 * Reconstruct a complete rocketh deployment record from address book metadata
 *
 * This enables verification and other operations that need full deployment records,
 * without storing the large records in the repo.
 *
 * @param addressBook - Address book ops instance
 * @param contractName - Name of the contract
 * @param artifact - Artifact source for ABI and bytecode
 * @returns Reconstructed deployment record, or undefined if metadata is incomplete
 */
export function reconstructDeploymentRecord(
  addressBook: AnyAddressBookOps,
  contractName: string,
  artifact: ArtifactSource,
):
  | {
      address: `0x${string}`
      abi: readonly unknown[]
      bytecode: `0x${string}`
      deployedBytecode?: `0x${string}`
      argsData: `0x${string}`
      metadata: string
    }
  | undefined {
  if (!addressBook.entryExists(contractName)) {
    return undefined
  }

  const entry = addressBook.getEntry(contractName)
  const deploymentMetadata = addressBook.getDeploymentMetadata(contractName)

  // Need at minimum argsData to reconstruct
  if (!deploymentMetadata?.argsData) {
    return undefined
  }

  // Verify bytecode hash matches if available
  const loadedArtifact = loadArtifactFromSource(artifact)
  if (!loadedArtifact) {
    return undefined
  }

  if (deploymentMetadata.bytecodeHash && loadedArtifact.deployedBytecode) {
    const localHash = computeBytecodeHash(loadedArtifact.deployedBytecode)
    if (deploymentMetadata.bytecodeHash !== localHash) {
      // Bytecode has changed - cannot reconstruct reliably
      return undefined
    }
  }

  return {
    address: entry.address as `0x${string}`,
    abi: (loadedArtifact.abi ?? []) as readonly unknown[],
    bytecode: (loadedArtifact.bytecode ?? '0x') as `0x${string}`,
    deployedBytecode: loadedArtifact.deployedBytecode as `0x${string}` | undefined,
    argsData: deploymentMetadata.argsData as `0x${string}`,
    metadata: '',
  }
}

/**
 * Create deployment metadata from a deployment result
 *
 * Helper to create DeploymentMetadata from rocketh deployment results
 * for storage in address book.
 *
 * @param txHash - Transaction hash of deployment
 * @param argsData - ABI-encoded constructor arguments
 * @param deployedBytecode - Deployed bytecode for hash computation
 * @param blockNumber - Block number of deployment
 * @param timestamp - Block timestamp (ISO 8601)
 */
export function createDeploymentMetadata(
  txHash: string,
  argsData: string,
  deployedBytecode: string,
  blockNumber?: number,
  timestamp?: string,
): DeploymentMetadata {
  return {
    txHash,
    argsData,
    bytecodeHash: computeBytecodeHash(deployedBytecode),
    ...(blockNumber !== undefined && { blockNumber }),
    ...(timestamp && { timestamp }),
  }
}

/**
 * Input for proxy status line generation
 */
interface ProxyStatusInput {
  /** Contract name */
  name: string
  /** Proxy address */
  proxyAddress: string
  /** Current implementation address */
  implAddress: string
  /** Pending implementation address (if any) */
  pendingAddress?: string
  /** Sync-specific status icon override: ↑ (upgraded), ↻ (synced) */
  syncIcon?: string
  /** Sync-specific notes to prepend (e.g., "upgraded from 0x...", "impl synced") */
  syncNotes?: string[]
  /** Whether local bytecode differs from deployed (shows △ icon) */
  codeChanged?: boolean
}

/**
 * Result of proxy status line generation
 */
interface ProxyStatusResult {
  /** Formatted status line */
  line: string
}

/**
 * Generate proxy contract status line
 *
 * Format: [codeIcon] [statusIcon] ContractName @ proxyAddr → implAddr (notes)
 * - codeIcon: ✓ (ok), △ (code changed)
 * - statusIcon: ◷ (pending), ↑ (upgraded), ↻ (synced), ' ' (none)
 *
 * @param input - Proxy status input data
 */
function formatProxyStatusLine(input: ProxyStatusInput): ProxyStatusResult {
  const codeIcon = input.codeChanged ? '△' : '✓'
  let statusIcon = input.syncIcon ?? ' '
  const notes: string[] = [...(input.syncNotes ?? [])]

  // Check for pending implementation (only set icon if no sync override)
  if (input.pendingAddress) {
    if (!input.syncIcon) {
      statusIcon = '◷'
    }
    notes.push(`pending upgrade to ${formatAddress(input.pendingAddress)}`)
  }

  // Add code changed note if applicable and not already implied by sync notes
  if (input.codeChanged && !input.pendingAddress && !input.syncNotes?.length) {
    notes.push('code changed')
  }

  // Format the line
  const suffix = notes.length > 0 ? ` (${notes.join(', ')})` : ''
  const line = `${codeIcon} ${statusIcon} ${input.name} @ ${formatAddress(input.proxyAddress)} → ${formatAddress(input.implAddress)}${suffix}`

  return { line }
}

/**
 * Specification for a contract to sync
 */
export interface ContractSpec {
  name: string
  /** Which address book this contract belongs to */
  addressBookType: AddressBookType
  address: string
  /** If true, contract must exist on-chain (prerequisite). If false, may not exist yet. */
  prerequisite: boolean
  /** External artifact to load ABI from */
  artifactName?: string
  /** Artifact source for loading ABI (if provided, ABI is saved to deployment record) */
  artifact?: ArtifactSource
  /** If true, address-only placeholder (code not required) */
  addressOnly?: boolean
  /** Proxy sync fields (if present, will sync implementation with on-chain) */
  proxy?: {
    proxyAdminAddress: string
    proxyType: 'graph' | 'transparent'
    bookImpl: string | undefined
    bookPending: string | undefined
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    addressBook: any
    /** Artifact source for bytecode hash comparison */
    artifact?: ArtifactSource
  }
}

/**
 * A group of contracts from the same address book
 */
export interface AddressBookGroup {
  label: string
  contracts: ContractSpec[]
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  addressBook?: any
}

/**
 * Build a ContractSpec from registry metadata and address book entry
 *
 * @param addressBookType - Which address book this contract belongs to
 * @param contractName - The deployment record name (key in CONTRACT_REGISTRY)
 * @param metadata - Contract metadata from registry
 * @param addressBook - The address book instance to read from
 * @param targetChainId - Chain ID for error messages
 */
export function buildContractSpec(
  addressBookType: AddressBookType,
  contractName: string,
  metadata: ContractMetadata,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  addressBook: any,
  targetChainId: number,
): ContractSpec {
  const addressBookEntryName = getAddressBookEntryName(addressBookType, contractName)

  // Get entry from address book
  const entry = addressBook.entryExists(addressBookEntryName) ? addressBook.getEntry(addressBookEntryName) : null

  if (!entry && metadata.prerequisite) {
    throw new Error(`${addressBookEntryName} not found in address book for chainId ${targetChainId}`)
  }

  const spec: ContractSpec = {
    name: contractName,
    addressBookType,
    address: entry?.address ?? '',
    prerequisite: metadata.prerequisite ?? false,
    artifact: metadata.artifact,
    addressOnly: metadata.addressOnly,
  }

  // Add proxy configuration if this is a proxied contract
  if (metadata.proxyType && entry) {
    // Get proxy admin address - either from entry or from a separate address book entry
    let proxyAdminAddress: string
    if (entry.proxyAdmin) {
      // Proxy admin stored inline in contract entry (e.g., SubgraphService)
      proxyAdminAddress = entry.proxyAdmin
    } else if (metadata.proxyAdminName) {
      // Proxy admin is a separate address book entry (e.g., GraphProxyAdmin)
      const adminEntryName = getAddressBookEntryName(addressBookType, metadata.proxyAdminName)
      const adminEntry = addressBook.entryExists(adminEntryName) ? addressBook.getEntry(adminEntryName) : null
      if (!adminEntry) {
        throw new Error(`${adminEntryName} not found in address book for chainId ${targetChainId}`)
      }
      proxyAdminAddress = adminEntry.address
    } else {
      throw new Error(`No proxy admin address found for ${contractName} (missing proxyAdminName and entry.proxyAdmin)`)
    }

    spec.proxy = {
      proxyAdminAddress,
      proxyType: metadata.proxyType,
      bookImpl: entry.implementation,
      bookPending: entry.pendingImplementation?.address,
      addressBook,
      artifact: metadata.artifact,
    }
  }

  return spec
}

/**
 * Result of syncing contracts
 */
export interface SyncResult {
  success: boolean
  totalSynced: number
  failures: string[]
}

/**
 * Sync a single contract - returns status and whether it succeeded
 */
async function syncContract(
  env: Environment,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  client: any,
  spec: ContractSpec,
): Promise<{ success: boolean; status: string }> {
  // Handle contracts with empty/zero addresses (not deployed yet)
  if (!spec.address || spec.address === '0x0000000000000000000000000000000000000000') {
    if (spec.prerequisite) {
      return { success: false, status: `❌   ${spec.name}: missing address (prerequisite)` }
    }
    return { success: true, status: `○   ${spec.name} (not deployed)` }
  }

  // Address-only entries don't require code - just display the address
  if (spec.addressOnly) {
    return { success: true, status: `✓   ${spec.name} @ ${formatAddress(spec.address)}` }
  }

  // Sync-specific icons and notes (determined by sync operations)
  let syncIcon: string | undefined
  const syncNotes: string[] = []

  // If this is a proxy, sync implementation with on-chain state first
  if (spec.proxy) {
    try {
      const onChainImpl = await getOnChainImplementation(
        client,
        spec.address,
        spec.proxy.proxyType,
        spec.proxy.proxyAdminAddress,
      )

      const bookImplMatches = spec.proxy.bookImpl?.toLowerCase() === onChainImpl.toLowerCase()

      if (!bookImplMatches) {
        // On-chain impl differs from address book - reconcile
        const oldImpl = spec.proxy.bookImpl
        const pendingMatches = spec.proxy.bookPending?.toLowerCase() === onChainImpl.toLowerCase()

        if (pendingMatches) {
          // Pending was upgraded on-chain → promote with metadata
          spec.proxy.addressBook.promotePendingImplementationWithMetadata(spec.name)
          syncIcon = '↑'
          syncNotes.push(oldImpl ? `upgraded from ${formatAddress(oldImpl)}` : 'upgraded')
        } else {
          // External change (not through pending) → update address, wipe stale metadata
          spec.proxy.addressBook.setImplementation(spec.name, onChainImpl)
          spec.proxy.addressBook.setImplementationDeploymentMetadata(spec.name, {
            txHash: '',
            argsData: '0x',
            bytecodeHash: '',
          })
          syncIcon = '↻'
          syncNotes.push(oldImpl ? `on-chain changed from ${formatAddress(oldImpl)}` : 'on-chain changed')
        }
      } else if (spec.proxy.bookPending) {
        if (spec.proxy.bookPending.toLowerCase() === onChainImpl.toLowerCase()) {
          // Pending matches on-chain impl but book impl already matched - promote pending
          spec.proxy.addressBook.promotePendingImplementationWithMetadata(spec.name)
          syncNotes.push('pending promoted')
        }
        // Note: if pending doesn't match on-chain, it's still pending - formatProxyStatusLine handles ◷ icon
      }

      // Get updated entry for formatProxyStatusLine
      const updatedEntry = spec.proxy.addressBook.getEntry(spec.name)

      // Check if local bytecode differs from deployed (via bytecodeHash)
      // If artifact exists but no bytecodeHash stored, assume code changed (untracked state)
      let codeChanged = false
      if (spec.proxy.artifact) {
        const deploymentMetadata = spec.proxy.addressBook.getDeploymentMetadata(spec.name)
        const localArtifact = loadArtifactFromSource(spec.proxy.artifact)
        if (deploymentMetadata?.bytecodeHash && localArtifact?.deployedBytecode) {
          const localHash = computeBytecodeHash(localArtifact.deployedBytecode)
          codeChanged = localHash !== deploymentMetadata.bytecodeHash
        } else if (localArtifact?.deployedBytecode) {
          // No stored bytecodeHash but artifact exists - untracked/legacy state
          codeChanged = true
        }
      }

      const result = formatProxyStatusLine({
        name: spec.name,
        proxyAddress: spec.address,
        implAddress: updatedEntry.implementation,
        pendingAddress: updatedEntry.pendingImplementation?.address,
        syncIcon,
        syncNotes,
        codeChanged,
      })

      // Check for code on-chain (still needed for non-proxy parts below)
      const code = await client.getCode({ address: spec.address as `0x${string}` })
      if (!code || code === '0x') {
        if (spec.prerequisite) {
          return { success: false, status: `❌   ${spec.name} @ ${formatAddress(spec.address)}: no code on-chain` }
        }
        return { success: false, status: `❌   ${spec.name} @ ${formatAddress(spec.address)}: stale (no code)` }
      }

      // Save deployment records for proxy
      // CRITICAL: Only set rocketh bytecode when NO existing record.
      // If rocketh already has a record, preserve its bytecode - it came from
      // a real deployment and rocketh's native change detection depends on it.
      // The backfill logic (rocketh → address book) handles the other direction.
      const existing = env.getOrNull(spec.name)
      const addressChanged = existing && existing.address.toLowerCase() !== spec.address.toLowerCase()

      if (!existing) {
        // No existing record - create from artifact
        let abi: readonly unknown[] = []
        let bytecode: `0x${string}` = '0x'
        let deployedBytecode: `0x${string}` | undefined
        if (spec.artifact) {
          const artifact = loadArtifactFromSource(spec.artifact)
          if (artifact?.abi) {
            abi = artifact.abi
          }
          if (artifact?.bytecode) {
            bytecode = artifact.bytecode as `0x${string}`
          }
          if (artifact?.deployedBytecode) {
            deployedBytecode = artifact.deployedBytecode as `0x${string}`
          }
        }
        await env.save(spec.name, {
          address: spec.address as `0x${string}`,
          abi: abi as typeof abi & readonly unknown[],
          bytecode,
          deployedBytecode,
          argsData: '0x' as `0x${string}`,
          metadata: '',
        } as unknown as Parameters<typeof env.save>[1])
      } else if (addressChanged) {
        // Address changed - update address but preserve existing bytecode
        // This handles the case where address book points to new address
        let abi: readonly unknown[] = existing.abi as readonly unknown[]
        // Update ABI from artifact if available (ABI doesn't affect change detection)
        if (spec.artifact) {
          const artifact = loadArtifactFromSource(spec.artifact)
          if (artifact?.abi) {
            abi = artifact.abi
          }
        }
        await env.save(spec.name, {
          address: spec.address as `0x${string}`,
          abi: abi as typeof abi & readonly unknown[],
          bytecode: existing.bytecode as `0x${string}`,
          deployedBytecode: existing.deployedBytecode as `0x${string}`,
          argsData: existing.argsData as `0x${string}`,
          metadata: existing.metadata ?? '',
        } as unknown as Parameters<typeof env.save>[1])
      }
      // else: existing record with same address - do nothing, preserve rocketh's state

      // Save proxy deployment record (rocketh expects {name}_Proxy)
      const proxyDeploymentName = `${spec.name}_Proxy`
      const proxyDeployment = env.getOrNull(proxyDeploymentName)
      if (!proxyDeployment || proxyDeployment.address.toLowerCase() !== spec.address.toLowerCase()) {
        await env.save(proxyDeploymentName, {
          address: spec.address as `0x${string}`,
          abi: [],
          bytecode: '0x' as `0x${string}`,
          argsData: '0x' as `0x${string}`,
          metadata: '',
        } as unknown as Parameters<typeof env.save>[1])
      }

      // Backfill proxy deployment metadata from rocketh if rocketh is newer
      const existingProxyDeployment = env.getOrNull(proxyDeploymentName)
      if (existingProxyDeployment?.argsData && existingProxyDeployment.argsData !== '0x') {
        const entry = spec.proxy.addressBook.getEntry(spec.name)
        const proxyRockethBlockNumber = existingProxyDeployment.receipt?.blockNumber
          ? parseInt(existingProxyDeployment.receipt.blockNumber as string)
          : undefined
        const proxyAddressBookBlockNumber = entry.proxyDeployment?.blockNumber

        // Backfill if:
        // - Address book has no proxy metadata at all
        // - Rocketh has blockNumber but address book doesn't (rocketh is newer)
        // - Rocketh has newer blockNumber
        const proxyRockethIsNewer =
          !entry.proxyDeployment?.argsData ||
          (proxyRockethBlockNumber !== undefined && proxyAddressBookBlockNumber === undefined) ||
          (proxyRockethBlockNumber !== undefined &&
            proxyAddressBookBlockNumber !== undefined &&
            proxyRockethBlockNumber > proxyAddressBookBlockNumber)

        if (proxyRockethIsNewer) {
          const proxyMetadata: DeploymentMetadata = {
            txHash: existingProxyDeployment.transaction?.hash ?? '',
            argsData: existingProxyDeployment.argsData,
            bytecodeHash: existingProxyDeployment.deployedBytecode
              ? computeBytecodeHash(existingProxyDeployment.deployedBytecode)
              : '',
            ...(proxyRockethBlockNumber !== undefined && { blockNumber: proxyRockethBlockNumber }),
          }
          spec.proxy.addressBook.setProxyDeploymentMetadata(spec.name, proxyMetadata)
          syncNotes.push('backfilled proxy metadata')
        }
      }

      // Save proxy admin deployment record
      const metadata = getContractMetadata(spec.addressBookType, spec.name)
      const proxyAdminDeploymentName = metadata?.proxyAdminName ?? `${spec.name}_ProxyAdmin`
      const proxyAdminDeployment = env.getOrNull(proxyAdminDeploymentName)
      if (
        !proxyAdminDeployment ||
        proxyAdminDeployment.address.toLowerCase() !== spec.proxy.proxyAdminAddress.toLowerCase()
      ) {
        // Load proxy admin ABI from its metadata if available
        let proxyAdminAbi: readonly unknown[] = []
        const proxyAdminMetadata = getContractMetadata(spec.addressBookType, proxyAdminDeploymentName)
        if (proxyAdminMetadata?.artifact) {
          const proxyAdminArtifact = loadArtifactFromSource(proxyAdminMetadata.artifact)
          if (proxyAdminArtifact?.abi) {
            proxyAdminAbi = proxyAdminArtifact.abi
          }
        }
        await env.save(proxyAdminDeploymentName, {
          address: spec.proxy.proxyAdminAddress as `0x${string}`,
          abi: proxyAdminAbi as typeof proxyAdminAbi & readonly unknown[],
          bytecode: '0x' as `0x${string}`,
          argsData: '0x' as `0x${string}`,
          metadata: '',
        } as unknown as Parameters<typeof env.save>[1])
      }

      // Save implementation deployment record
      // Pick pending or current - both have same structure (address + deployment metadata)
      const pendingImpl = updatedEntry.pendingImplementation
      const implAddress = pendingImpl?.address ?? updatedEntry.implementation
      const implDeployment = pendingImpl
        ? pendingImpl.deployment
        : spec.proxy.addressBook.getDeploymentMetadata(spec.name)

      if (implAddress) {
        const storedHash = implDeployment?.bytecodeHash

        // Only sync if stored hash matches local artifact
        let hashMatches = false
        if (storedHash && spec.proxy.artifact) {
          const localArtifact = loadArtifactFromSource(spec.proxy.artifact)
          if (localArtifact?.deployedBytecode) {
            const localHash = computeBytecodeHash(localArtifact.deployedBytecode)
            if (storedHash === localHash) {
              hashMatches = true
            } else {
              syncNotes.push('impl outdated')
            }
          }
        }

        if (hashMatches) {
          const implResult = await syncContract(env, client, {
            name: `${spec.name}_Implementation`,
            addressBookType: spec.addressBookType,
            address: implAddress,
            prerequisite: true,
          })
          if (!implResult.success) {
            return implResult
          }

          // Backfill address book metadata from rocketh if rocketh is newer
          const rockethImpl = env.getOrNull(`${spec.name}_Implementation`)
          if (rockethImpl?.argsData && rockethImpl.argsData !== '0x') {
            const rockethBlockNumber = rockethImpl.receipt?.blockNumber
              ? parseInt(rockethImpl.receipt.blockNumber as string)
              : undefined
            const bookBlockNumber = implDeployment?.blockNumber

            // Backfill if:
            // - Address book has no metadata at all
            // - Rocketh has blockNumber but address book doesn't (rocketh is newer)
            // - Rocketh has newer blockNumber
            const rockethIsNewer =
              !implDeployment?.argsData ||
              (rockethBlockNumber !== undefined && bookBlockNumber === undefined) ||
              (rockethBlockNumber !== undefined &&
                bookBlockNumber !== undefined &&
                rockethBlockNumber > bookBlockNumber)

            if (rockethIsNewer) {
              const metadata: DeploymentMetadata = {
                txHash: rockethImpl.transaction?.hash ?? '',
                argsData: rockethImpl.argsData,
                bytecodeHash: rockethImpl.deployedBytecode ? computeBytecodeHash(rockethImpl.deployedBytecode) : '',
                ...(rockethBlockNumber !== undefined && { blockNumber: rockethBlockNumber }),
              }
              // Write to correct location based on pending vs current
              if (pendingImpl) {
                spec.proxy.addressBook.setPendingDeploymentMetadata(spec.name, metadata)
              } else {
                spec.proxy.addressBook.setImplementationDeploymentMetadata(spec.name, metadata)
              }
              syncNotes.push('backfilled metadata')
            }
          }
        }
      }

      return { success: true, status: result.line }
    } catch (error) {
      return {
        success: false,
        status: `⚠️   ${spec.name}: could not read on-chain state: ${(error as Error).message}`,
      }
    }
  }

  // Non-proxy contract handling
  // Note: Proxy contracts return early above, so we only reach here for non-proxies
  let nonProxySyncIcon = ' '
  const statusNotes: string[] = []

  // Verify code exists on-chain (just checking existence, not storing bytecode)
  try {
    const code = await client.getCode({ address: spec.address as `0x${string}` })
    if (!code || code === '0x') {
      if (spec.prerequisite) {
        return { success: false, status: `❌   ${spec.name} @ ${formatAddress(spec.address)}: no code on-chain` }
      }
      // Non-prerequisite with address but no code - stale state
      return { success: false, status: `❌   ${spec.name} @ ${formatAddress(spec.address)}: stale (no code)` }
    }
  } catch (error) {
    return {
      success: false,
      status: `⚠️   ${spec.name} @ ${formatAddress(spec.address)}: ${(error as Error).message}`,
    }
  }

  // Check existing deployment record
  // CRITICAL: Only set rocketh bytecode when NO existing record.
  // If rocketh already has a record, preserve its bytecode - it came from
  // a real deployment and rocketh's native change detection depends on it.
  const existing = env.getOrNull(spec.name)
  const addressChanged = existing && existing.address.toLowerCase() !== spec.address.toLowerCase()

  if (existing && addressChanged) {
    nonProxySyncIcon = '↻'
    statusNotes.push('re-imported')
  }

  if (!existing) {
    // No existing record - create from artifact
    let abi: readonly unknown[] = []
    let bytecode: `0x${string}` = '0x'
    let deployedBytecode: `0x${string}` | undefined
    if (spec.artifact) {
      const artifact = loadArtifactFromSource(spec.artifact)
      if (artifact?.abi) {
        abi = artifact.abi
      }
      if (artifact?.bytecode) {
        bytecode = artifact.bytecode as `0x${string}`
      }
      if (artifact?.deployedBytecode) {
        deployedBytecode = artifact.deployedBytecode as `0x${string}`
      }
    }
    await env.save(spec.name, {
      address: spec.address as `0x${string}`,
      abi: abi as typeof abi & readonly unknown[],
      bytecode,
      deployedBytecode,
      argsData: '0x' as `0x${string}`,
      metadata: '',
    } as unknown as Parameters<typeof env.save>[1])
  } else if (addressChanged) {
    // Address changed - update address but preserve existing bytecode
    let abi: readonly unknown[] = existing.abi as readonly unknown[]
    if (spec.artifact) {
      const artifact = loadArtifactFromSource(spec.artifact)
      if (artifact?.abi) {
        abi = artifact.abi
      }
    }
    await env.save(spec.name, {
      address: spec.address as `0x${string}`,
      abi: abi as typeof abi & readonly unknown[],
      bytecode: existing.bytecode as `0x${string}`,
      deployedBytecode: existing.deployedBytecode as `0x${string}`,
      argsData: existing.argsData as `0x${string}`,
      metadata: existing.metadata ?? '',
    } as unknown as Parameters<typeof env.save>[1])
  }
  // else: existing record with same address - do nothing, preserve rocketh's state

  // Format status line for non-proxy contracts (two-column format with blank status icon position)
  const statusSuffix = statusNotes.length > 0 ? ` (${statusNotes.join(', ')})` : ''
  return { success: true, status: `✓ ${nonProxySyncIcon} ${spec.name} @ ${formatAddress(spec.address)}${statusSuffix}` }
}

/**
 * Sync contract groups with on-chain state
 *
 * For each contract:
 * - Sync proxy implementations with on-chain state
 * - Import contract addresses into rocketh deployment records
 * - Validate prerequisites exist on-chain
 * - Show code changed indicator (△) when local bytecode differs from deployed
 */
export async function syncContractGroups(env: Environment, groups: AddressBookGroup[]): Promise<SyncResult> {
  const client = graph.getPublicClient(env)
  const failures: string[] = []
  let totalSynced = 0

  for (const group of groups) {
    env.showMessage(`\n📦 ${group.label}`)

    for (const spec of group.contracts) {
      const result = await syncContract(env, client, spec)

      env.showMessage(`  ${result.status}`)
      if (!result.success) {
        failures.push(spec.name)
      } else {
        totalSynced++
        // For proxies, syncContract also syncs the implementation internally
        if (spec.proxy) {
          totalSynced++ // Count the implementation sync
        }
      }
    }
  }

  return { success: failures.length === 0, totalSynced, failures }
}

/**
 * Contract status result (read-only, no sync operations)
 */
export interface ContractStatusResult {
  /** Status line to display */
  line: string
  /** Whether contract exists on-chain */
  exists: boolean
  /** Optional warnings (e.g., address book stale) */
  warnings?: string[]
}

/**
 * Get contract status line (read-only, no sync operations)
 *
 * Returns a formatted status line similar to sync output:
 * - ✓ = ok, △ = code changed, ◷ = pending upgrade, ○ = not deployed, ❌ = error
 *
 * @param client - Viem public client
 * @param addressBookType - Which address book this contract belongs to
 * @param addressBook - Address book instance
 * @param contractName - Name of the contract in the registry
 * @param metadata - Contract metadata from registry (optional, will look up if not provided)
 */
export async function getContractStatusLine(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  client: any,
  addressBookType: AddressBookType,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  addressBook: any,
  contractName: string,
  metadata?: ContractMetadata,
): Promise<ContractStatusResult> {
  const meta = metadata ?? getContractMetadata(addressBookType, contractName)
  const entryName = getAddressBookEntryName(addressBookType, contractName)

  try {
    const entry = addressBook.entryExists(entryName) ? addressBook.getEntry(entryName) : null
    if (!entry?.address) {
      return { line: `○   ${contractName} (not deployed)`, exists: false }
    }

    // Address-only entries don't require code
    if (meta?.addressOnly) {
      return { line: `✓   ${contractName} @ ${formatAddress(entry.address)}`, exists: true }
    }

    // Check if code exists on-chain
    const code = await client.getCode({ address: entry.address as `0x${string}` })
    if (!code || code === '0x') {
      return { line: `❌   ${contractName} @ ${formatAddress(entry.address)}: no code`, exists: false }
    }

    // For proxies, read actual on-chain implementation (not address book's possibly-stale value)
    if (meta?.proxyType) {
      // Get proxy admin address
      let proxyAdminAddress: string | undefined
      if (entry.proxyAdmin) {
        proxyAdminAddress = entry.proxyAdmin
      } else if (meta.proxyAdminName) {
        const adminEntryName = getAddressBookEntryName(addressBookType, meta.proxyAdminName)
        proxyAdminAddress = addressBook.entryExists(adminEntryName)
          ? addressBook.getEntry(adminEntryName)?.address
          : undefined
      }

      // Read actual implementation from chain
      let actualImpl: string | undefined
      try {
        actualImpl = await getOnChainImplementation(client, entry.address, meta.proxyType, proxyAdminAddress)
      } catch {
        // Fall back to address book if on-chain read fails
        actualImpl = entry.implementation
      }

      if (actualImpl) {
        // Check if local bytecode differs from deployed (via bytecodeHash)
        // If artifact exists but no bytecodeHash stored, assume code changed (untracked state)
        let codeChanged = false
        if (meta.artifact) {
          const deploymentMetadata = addressBook.getDeploymentMetadata(contractName)
          const localArtifact = loadArtifactFromSource(meta.artifact)
          if (deploymentMetadata?.bytecodeHash && localArtifact?.deployedBytecode) {
            const localHash = computeBytecodeHash(localArtifact.deployedBytecode)
            codeChanged = localHash !== deploymentMetadata.bytecodeHash
          } else if (localArtifact?.deployedBytecode) {
            // No stored bytecodeHash but artifact exists - untracked/legacy state
            codeChanged = true
          }
        }

        const result = formatProxyStatusLine({
          name: contractName,
          proxyAddress: entry.address,
          implAddress: actualImpl,
          pendingAddress: entry.pendingImplementation?.address,
          codeChanged,
        })

        // Check if address book is stale (on-chain impl differs from recorded impl)
        const warnings: string[] = []
        const bookImpl = entry.implementation
        if (bookImpl && actualImpl.toLowerCase() !== bookImpl.toLowerCase()) {
          warnings.push(`address book stale: recorded impl ${formatAddress(bookImpl)}`)
        }

        return { line: result.line, exists: true, warnings: warnings.length > 0 ? warnings : undefined }
      }
    }

    // Non-proxy contract - use two-column format with blank status icon
    return { line: `✓   ${contractName} @ ${formatAddress(entry.address)}`, exists: true }
  } catch {
    return { line: `⚠   ${contractName}: error reading`, exists: false }
  }
}
