import { existsSync } from 'node:fs'

import type { Artifact, Environment } from '@rocketh/core/types'
import type { DeploymentMetadata } from '@graphprotocol/toolshed/deployments'

import {
  autoDetectForkNetwork,
  getForkNetwork,
  getForkStateDir,
  getForkTargetChainId,
  getIssuanceAddressBookPath,
  getTargetChainIdFromEnv,
  isForkMode,
} from './address-book-utils.js'
import {
  getLibraryResolver,
  loadContractsArtifact,
  loadHorizonBuildArtifact,
  loadIssuanceArtifact,
  loadOpenZeppelinArtifact,
  loadSubgraphServiceArtifact,
} from './artifact-loaders.js'
import { computeBytecodeHash } from './bytecode-utils.js'
import {
  type AddressBookType,
  type ArtifactSource,
  type ContractMetadata,
  type RegistryEntry,
  getAddressBookEntryName,
  getContractMetadata,
  getContractsByAddressBook,
} from './contract-registry.js'
import { SpecialTags } from './deployment-tags.js'
import { getOnChainImplementation } from './deploy-implementation.js'
import { graph } from '../rocketh/deploy.js'
import type { AnyAddressBookOps } from './address-book-ops.js'

/**
 * Format an address based on SHOW_ADDRESSES environment variable
 * - 0: return empty string (no addresses shown)
 * - 1: return truncated address (0x1234...5678)
 * - 2 (default): return full address
 */
function formatAddress(address: string): string {
  const showAddresses = process.env.SHOW_ADDRESSES ?? '2'

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
      case 'horizon':
        return loadHorizonBuildArtifact(source.path)
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
      const libResolver = getLibraryResolver(artifact.type)
      const localHash = computeBytecodeHash(
        loadedArtifact.deployedBytecode,
        loadedArtifact.deployedLinkReferences,
        libResolver,
      )
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
    const libResolver = getLibraryResolver(artifact.type)
    const localHash = computeBytecodeHash(
      loadedArtifact.deployedBytecode,
      loadedArtifact.deployedLinkReferences,
      libResolver,
    )
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
 * Check if local artifact bytecode differs from what was last deployed.
 *
 * Compares the local artifact's bytecodeHash against the stored hash in the
 * address book. The stored hash is recorded from the local artifact at deploy
 * time, so this is a local-to-local comparison (no on-chain bytecode fetch).
 *
 * @returns codeChanged flag and the computed localHash (needed for hashMatches checks)
 */
function checkCodeChanged(
  artifactSource: ArtifactSource | undefined,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  addressBook: any,
  contractName: string,
): { codeChanged: boolean; localHash?: string } {
  if (!artifactSource) return { codeChanged: false }

  const localArtifact = loadArtifactFromSource(artifactSource)
  const resolver = getLibraryResolver(artifactSource.type)
  const localHash = localArtifact?.deployedBytecode
    ? computeBytecodeHash(localArtifact.deployedBytecode, localArtifact.deployedLinkReferences, resolver)
    : undefined

  const deploymentMetadata = addressBook.getDeploymentMetadata(contractName)
  if (deploymentMetadata?.bytecodeHash && localHash) {
    return { codeChanged: localHash !== deploymentMetadata.bytecodeHash, localHash }
  }
  if (localArtifact?.deployedBytecode) {
    // No stored bytecodeHash but artifact exists - untracked/legacy state
    return { codeChanged: true, localHash }
  }
  return { codeChanged: false, localHash }
}

/**
 * Proxy admin ownership state
 */
export type ProxyAdminOwner = 'governor' | 'deployer' | 'other' | 'unknown'

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
  /** ProxyAdmin ownership state — 'deployer' shows 🔑 warning icon */
  proxyAdminOwner?: ProxyAdminOwner
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

  // ProxyAdmin ownership warning: 🔑 when known to be non-governor (deployer or other)
  const adminIcon =
    input.proxyAdminOwner && input.proxyAdminOwner !== 'governor' && input.proxyAdminOwner !== 'unknown' ? ' 🔑' : ''

  // Format the line
  const suffix = notes.length > 0 ? ` (${notes.join(', ')})` : ''
  const line = `${codeIcon} ${statusIcon} ${input.name} @ ${formatAddress(input.proxyAddress)} → ${formatAddress(input.implAddress)}${suffix}${adminIcon}`

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
  /** ABI-encoded constructor args from address book deployment metadata.
   *  Used to seed rocketh records with real argsData instead of '0x'. */
  deploymentArgsData?: string
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

  // Get deployment argsData from address book for accurate rocketh record seeding
  let deploymentArgsData: string | undefined
  if (entry) {
    const deploymentMeta = entry.proxy ? entry.implementationDeployment : entry.deployment
    if (deploymentMeta?.argsData && deploymentMeta.argsData !== '0x') {
      deploymentArgsData = deploymentMeta.argsData
    }
  }

  const spec: ContractSpec = {
    name: contractName,
    addressBookType,
    address: entry?.address ?? '',
    prerequisite: metadata.prerequisite ?? false,
    artifact: metadata.artifact,
    addressOnly: metadata.addressOnly,
    deploymentArgsData,
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
export async function syncContract(
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

      const pendingImpl = updatedEntry.pendingImplementation
      const implAddress = pendingImpl?.address ?? updatedEntry.implementation
      const implDeployment = pendingImpl
        ? pendingImpl.deployment
        : spec.proxy.addressBook.getDeploymentMetadata(spec.name)

      const { codeChanged, localHash } = checkCodeChanged(spec.proxy.artifact, spec.proxy.addressBook, spec.name)

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
        // IMPORTANT: For proxy contracts, we only load the ABI, not bytecode
        // The artifact is for the implementation, not the proxy itself
        let abi: readonly unknown[] = []
        if (spec.artifact) {
          const artifact = loadArtifactFromSource(spec.artifact)
          if (artifact?.abi) {
            abi = artifact.abi
          }
        }
        await env.save(spec.name, {
          address: spec.address as `0x${string}`,
          abi: abi as typeof abi & readonly unknown[],
          bytecode: '0x' as `0x${string}`, // Don't store impl bytecode for proxy record
          deployedBytecode: undefined,
          argsData: '0x' as `0x${string}`,
          metadata: '',
        } as unknown as Parameters<typeof env.save>[1])
      } else if (addressChanged) {
        // Address changed - update address and clear bytecode (proxy address changed)
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
          bytecode: '0x' as `0x${string}`, // Clear bytecode - proxy changed
          deployedBytecode: undefined,
          argsData: '0x' as `0x${string}`,
          metadata: '',
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

      // Save implementation deployment record (if local hash matches stored)
      if (implAddress) {
        const storedHash = implDeployment?.bytecodeHash
        let hashMatches = false

        if (storedHash && localHash) {
          hashMatches = storedHash === localHash
        }

        // When hash doesn't match, leave the existing rocketh record untouched.
        // The old record (with real bytecode from the previous deploy) lets rocketh
        // correctly detect the bytecode change and trigger a fresh deployment.
        // NOTE: Do NOT clear the record to bytecode '0x' — rocketh's CBOR-stripping
        // comparison treats '0x' as NaN length, causing slice(0, NaN) → '' for both
        // old and new bytecodes, making them falsely compare as equal.

        if (hashMatches) {
          const implResult = await syncContract(env, client, {
            name: `${spec.name}_Implementation`,
            addressBookType: spec.addressBookType,
            address: implAddress,
            prerequisite: true,
            artifact: spec.proxy.artifact,
          })
          if (!implResult.success) {
            return implResult
          }

          // Patch implementation record with deployment metadata for accurate
          // rocketh comparison. syncContract creates bare records without argsData,
          // but rocketh's deploy() compares argsData to decide if redeployment is
          // needed. Without the real argsData, rocketh falsely detects a change
          // and redeploys implementations that haven't changed.
          const implRecordName = `${spec.name}_Implementation`
          const implRecord = env.getOrNull(implRecordName)
          if (implRecord && implDeployment?.argsData && (!implRecord.argsData || implRecord.argsData === '0x')) {
            await env.save(implRecordName, {
              address: implRecord.address as `0x${string}`,
              abi: implRecord.abi as typeof implRecord.abi & readonly unknown[],
              bytecode: (implRecord.bytecode ?? '0x') as `0x${string}`,
              deployedBytecode: implRecord.deployedBytecode as `0x${string}` | undefined,
              argsData: implDeployment.argsData as `0x${string}`,
              metadata: (implRecord as Record<string, unknown>).metadata ?? '',
            } as unknown as Parameters<typeof env.save>[1])
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
      argsData: (spec.deploymentArgsData ?? '0x') as `0x${string}`,
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

  // Backfill deployment metadata from rocketh → address book (mirrors proxy backfill)
  // Only for real registry entries — skip synthetic names (e.g. HorizonStaking_Implementation)
  // created by proxy sync as rocketh-only records
  const registryMetadata = getContractMetadata(spec.addressBookType, spec.name)
  const rockethRecord = env.getOrNull(spec.name)
  if (registryMetadata && rockethRecord?.argsData && rockethRecord.argsData !== '0x') {
    const chainId = await getTargetChainIdFromEnv(env)
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const addressBook: any = getAddressBookForType(spec.addressBookType, chainId)
    const entry = addressBook.getEntry(spec.name)
    const rockethBlockNumber = rockethRecord.receipt?.blockNumber
      ? parseInt(rockethRecord.receipt.blockNumber as string)
      : undefined
    const addressBookBlockNumber = entry.deployment?.blockNumber

    const rockethIsNewer =
      !entry.deployment?.argsData ||
      (rockethBlockNumber !== undefined && addressBookBlockNumber === undefined) ||
      (rockethBlockNumber !== undefined &&
        addressBookBlockNumber !== undefined &&
        rockethBlockNumber > addressBookBlockNumber)

    if (rockethIsNewer) {
      const deploymentMetadata: DeploymentMetadata = {
        txHash: rockethRecord.transaction?.hash ?? '',
        argsData: rockethRecord.argsData,
        bytecodeHash: rockethRecord.deployedBytecode ? computeBytecodeHash(rockethRecord.deployedBytecode) : '',
        ...(rockethBlockNumber !== undefined && { blockNumber: rockethBlockNumber }),
      }
      addressBook.setDeploymentMetadata(spec.name, deploymentMetadata)
      statusNotes.push('backfilled metadata')
    }
  }

  // Format status line for non-proxy contracts (two-column format with blank status icon position)
  const statusSuffix = statusNotes.length > 0 ? ` (${statusNotes.join(', ')})` : ''
  return { success: true, status: `✓ ${nonProxySyncIcon} ${spec.name} @ ${formatAddress(spec.address)}${statusSuffix}` }
}

/**
 * Options for sync display filtering
 */
export interface SyncOptions {
  /**
   * Tags requested in the deploy command (e.g., ['IssuanceAllocator:deploy', 'sync']).
   * When set, only contracts matching these tags or with detected changes are displayed.
   * Sync still runs for all contracts regardless of filter.
   */
  tagFilter?: string[]
}

/**
 * Extract component names from deployment tags.
 *
 * Strips action suffixes (e.g., 'IssuanceAllocator:deploy' → 'IssuanceAllocator')
 * and filters out the special 'sync' tag.
 */
function extractComponentNames(tags: string[]): Set<string> {
  const components = new Set<string>()
  for (const tag of tags) {
    if (tag === SpecialTags.SYNC) continue
    components.add(tag.split(':')[0])
  }
  return components
}

/**
 * Check whether a sync status line indicates changes were detected.
 *
 * Icons: ↑ upgraded, ↻ synced/re-imported, ◷ pending, △ code changed
 * Parenthetical notes also indicate notable state (but not "(not deployed)").
 */
function statusHasChanges(status: string): boolean {
  if (/[↑↻◷△]/.test(status)) return true
  if (status.includes('(') && !status.includes('(not deployed)')) return true
  return false
}

/**
 * Determine whether a contract's sync result should be displayed.
 */
function shouldDisplay(
  spec: ContractSpec,
  result: { success: boolean; status: string },
  filterComponents: Set<string> | null,
): boolean {
  if (!filterComponents) return true
  if (!result.success) return true
  if (statusHasChanges(result.status)) return true
  const metadata = getContractMetadata(spec.addressBookType, spec.name)
  return !!metadata?.componentTag && filterComponents.has(metadata.componentTag)
}

/**
 * Sync contract groups with on-chain state
 *
 * For each contract:
 * - Sync proxy implementations with on-chain state
 * - Import contract addresses into rocketh deployment records
 * - Validate prerequisites exist on-chain
 * - Show code changed indicator (△) when local bytecode differs from deployed
 *
 * When options.tagFilter is set, only contracts matching the requested tags
 * or with detected changes are displayed. Sync still runs for all contracts.
 */
export async function syncContractGroups(
  env: Environment,
  groups: AddressBookGroup[],
  options?: SyncOptions,
): Promise<SyncResult> {
  const client = graph.getPublicClient(env)
  const failures: string[] = []
  let totalSynced = 0

  // Build component filter from tags (null = no filtering)
  const filterComponents =
    options?.tagFilter && options.tagFilter.length > 0 ? extractComponentNames(options.tagFilter) : null
  const isFiltering = filterComponents !== null && filterComponents.size > 0
  let totalSuppressed = 0

  for (const group of groups) {
    // Buffer results so we can filter display without affecting sync
    const results: Array<{ spec: ContractSpec; result: { success: boolean; status: string } }> = []

    for (const spec of group.contracts) {
      const result = await syncContract(env, client, spec)
      results.push({ spec, result })

      if (!result.success) {
        failures.push(spec.name)
      } else {
        totalSynced++
        if (spec.proxy) {
          totalSynced++
        }
      }
    }

    // Filter which results to display
    const visible = isFiltering
      ? results.filter(({ spec, result }) => shouldDisplay(spec, result, filterComponents))
      : results
    const suppressed = results.length - visible.length
    totalSuppressed += suppressed

    if (visible.length > 0) {
      env.showMessage(`\n📦 ${group.label}`)
      for (const { result } of visible) {
        env.showMessage(`  ${result.status}`)
      }
      if (suppressed > 0) {
        env.showMessage(`  ... ${suppressed} unchanged`)
      }
    }
  }

  if (isFiltering && totalSuppressed > 0) {
    env.showMessage(`\n  ... ${totalSuppressed} unchanged contracts hidden (--tags sync for full output)`)
  }

  return { success: failures.length === 0, totalSynced, failures }
}

/**
 * Resolve address book instance for a given address book type and chain ID
 */
function getAddressBookForType(addressBookType: AddressBookType, chainId: number) {
  switch (addressBookType) {
    case 'horizon':
      return graph.getHorizonAddressBook(chainId)
    case 'subgraph-service':
      return graph.getSubgraphServiceAddressBook(chainId)
    case 'issuance':
      return graph.getIssuanceAddressBook(chainId)
  }
}

/**
 * Sync a single component from the contract registry with on-chain state.
 *
 * Resolves the address book, builds a ContractSpec, and runs the same sync
 * logic as the full sync script — reading on-chain state to confirm and
 * propagate reality into address books and rocketh records.
 *
 * Components call this immediately before and after mutating actions so the
 * action operates on a confirmed-fresh view, without requiring a separate
 * global sync to have run first.
 */
export async function syncComponentFromRegistry(env: Environment, contract: RegistryEntry): Promise<void> {
  const chainId = await getTargetChainIdFromEnv(env)
  const addressBook = getAddressBookForType(contract.addressBook, chainId)
  const metadata = getContractMetadata(contract.addressBook, contract.name)
  if (!metadata) {
    throw new Error(`Contract '${contract.name}' not found in ${contract.addressBook} registry`)
  }

  const spec = buildContractSpec(contract.addressBook, contract.name, metadata, addressBook, chainId)
  const client = graph.getPublicClient(env)
  const result = await syncContract(env, client, spec)

  env.showMessage(`  ${result.status}`)
  if (!result.success) {
    throw new Error(`Sync failed for ${contract.name}: ${result.status}`)
  }
}

/**
 * Sync multiple components from the contract registry with on-chain state.
 *
 * Convenience wrapper around `syncComponentFromRegistry` for scripts that need
 * a small set of contracts in sync before they read them — typically the
 * contract being acted on plus its direct on-chain prerequisites (Controller,
 * shared implementations, etc.).
 */
export async function syncComponentsFromRegistry(env: Environment, contracts: RegistryEntry[]): Promise<void> {
  for (const contract of contracts) {
    await syncComponentFromRegistry(env, contract)
  }
}

/**
 * Run the full address book sync across every deployable contract in every
 * address book (Horizon, SubgraphService, Issuance).
 *
 * This is the implementation behind both the `00_sync.ts` deploy script (run
 * via `--tags sync`) and the `deploy:sync` Hardhat task. Orchestration scripts
 * that need many contracts in sync before they run (e.g. the GIP-0088 upgrade
 * batch builder) call this directly instead of relying on a tag dependency.
 *
 * On failure, exits the process with code 1 after printing remediation hints.
 */
export async function runFullSync(env: Environment): Promise<void> {
  // Get chainId from provider (will be 31337 in fork mode)
  const chainIdHex = await env.network.provider.request({ method: 'eth_chainId' })
  const providerChainId = Number(chainIdHex)

  // Auto-detect fork network from anvil if not explicitly set
  if (providerChainId === 31337 && !getForkNetwork(env.name)) {
    const detected = await autoDetectForkNetwork()
    if (detected) {
      env.showMessage(`\n🔍 Auto-detected fork network: ${detected}`)
    }
  }

  // Determine target chain ID for address book lookups
  const forkNetwork = getForkNetwork(env.name)
  const isForking = isForkMode(env.name)
  const forkChainId = getForkTargetChainId(env.name)
  const targetChainId = forkChainId ?? providerChainId

  // Check for common misconfiguration: localhost without FORK_NETWORK and not a detectable fork
  if (providerChainId === 31337 && !forkNetwork) {
    throw new Error(
      `Running on localhost (chainId 31337) without FORK_NETWORK set.\n\n` +
        `If you're testing against a forked network, set the environment variable:\n` +
        `  export FORK_NETWORK=arbitrumSepolia\n` +
        `  npx hardhat deploy:sync --network localhost\n\n` +
        `Or use ephemeral fork mode:\n` +
        `  HARDHAT_FORK=arbitrumSepolia npx hardhat deploy:sync`,
    )
  }

  if (forkNetwork) {
    const forkStateDir = getForkStateDir(env.name, forkNetwork)
    env.showMessage(`\n🔄 Sync: ${forkNetwork} fork (chainId: ${targetChainId})`)
    env.showMessage(`   Using fork-local address books (${forkStateDir}/)`)
  } else {
    env.showMessage(`\n🔄 Sync: ${env.name} (chainId: ${providerChainId})`)
  }

  // Get address books (automatically uses fork-local copies in fork mode)
  const horizonAddressBook = graph.getHorizonAddressBook(targetChainId)
  const ssAddressBook = graph.getSubgraphServiceAddressBook(targetChainId)

  const groups: AddressBookGroup[] = []

  // --- Horizon contracts ---
  const horizonContracts: ContractSpec[] = getDeployableContracts('horizon').map((name) => {
    const metadata = getContractMetadata('horizon', name)
    if (!metadata) throw new Error(`Contract ${name} not found in horizon registry`)
    return buildContractSpec('horizon', name, metadata, horizonAddressBook, targetChainId)
  })
  groups.push({ label: 'Horizon', contracts: horizonContracts, addressBook: horizonAddressBook })

  // --- SubgraphService contracts ---
  const ssContracts: ContractSpec[] = getDeployableContracts('subgraph-service').map((name) => {
    const metadata = getContractMetadata('subgraph-service', name)
    if (!metadata) throw new Error(`Contract ${name} not found in subgraph-service registry`)
    return buildContractSpec('subgraph-service', name, metadata, ssAddressBook, targetChainId)
  })
  groups.push({ label: 'SubgraphService', contracts: ssContracts, addressBook: ssAddressBook })

  // --- Issuance contracts ---
  const issuanceBookPath = getIssuanceAddressBookPath()
  const issuanceAddressBook = existsSync(issuanceBookPath) ? graph.getIssuanceAddressBook(targetChainId) : null

  if (issuanceAddressBook) {
    const issuanceContracts: ContractSpec[] = getDeployableContracts('issuance').map((name) => {
      const metadata = getContractMetadata('issuance', name)
      if (!metadata) throw new Error(`Contract ${name} not found in issuance registry`)
      return buildContractSpec('issuance', name, metadata, issuanceAddressBook, targetChainId)
    })
    if (issuanceContracts.length > 0) {
      groups.push({ label: 'Issuance', contracts: issuanceContracts, addressBook: issuanceAddressBook })
    }
  }

  // Parse --tags from process.argv to filter sync display when invoked via
  // `hardhat deploy --tags ...` (does nothing for the standalone deploy:sync task)
  const tagsIndex = process.argv.indexOf('--tags')
  const requestedTags =
    tagsIndex !== -1 && tagsIndex < process.argv.length - 1 ? process.argv[tagsIndex + 1].split(',') : []

  const syncOptions: SyncOptions = requestedTags.length > 0 ? { tagFilter: requestedTags } : {}

  const result = await syncContractGroups(env, groups, syncOptions)

  if (!result.success) {
    env.showMessage(`\n❌ Sync failed: address book does not match chain state.\n`)
    env.showMessage(`The following contracts are in address book but have no code on-chain:`)
    env.showMessage(`  ${result.failures.join(', ')}\n`)
    if (isForking) {
      env.showMessage(`This is likely because the fork was restarted.\n`)
      env.showMessage(`To fix, reset fork state and re-run:`)
      env.showMessage(`  npx hardhat deploy:reset-fork --network localhost`)
    } else {
      env.showMessage(`Possible causes:`)
      env.showMessage(`  1. Address book has incorrect addresses for this network`)
      env.showMessage(`  2. Running against wrong network`)
    }
    process.exit(1)
  }

  env.showMessage(`\n✅ Sync complete: ${result.totalSynced} contracts synced\n`)
}

/** Filter deployable contracts from a registry namespace. */
function getDeployableContracts(addressBook: AddressBookType): string[] {
  return getContractsByAddressBook(addressBook)
    .filter(([_, metadata]) => metadata.deployable !== false)
    .map(([name]) => name)
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
  /** Proxy admin ownership state (only for proxied contracts) */
  proxyAdminOwner?: ProxyAdminOwner
  /** Proxy admin address (only for proxied contracts) */
  proxyAdminAddress?: string
  /** Proxy admin owner address (only for proxied contracts with on-chain query) */
  proxyAdminOwnerAddress?: string
  /** Whether local compiled bytecode differs from deployed bytecode */
  codeChanged?: boolean
  /** Whether a pending implementation upgrade exists */
  hasPendingImplementation?: boolean
}

/**
 * Options for querying proxy admin ownership during status checks
 */
export interface ProxyAdminOwnershipContext {
  /** Governor address (from Controller) — required */
  governor: string
  /** Deployer address (from named accounts) — optional, used for labelling */
  deployer?: string
}

/**
 * Query ProxyAdmin ownership and classify as governor/deployer/unknown
 *
 * The 🔑 warning icon is shown for anything NOT governor-owned.
 * Deployer detection is best-effort (only when deployer address is known).
 */
async function queryProxyAdminOwnership(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  client: any,
  proxyAdminAddress: string,
  ctx: ProxyAdminOwnershipContext,
): Promise<{ owner: ProxyAdminOwner; ownerAddress: string }> {
  try {
    const ownerAddress = (await client.readContract({
      address: proxyAdminAddress as `0x${string}`,
      abi: [
        {
          inputs: [],
          name: 'owner',
          outputs: [{ type: 'address' }],
          stateMutability: 'view',
          type: 'function',
        },
      ],
      functionName: 'owner',
    })) as string

    if (ownerAddress.toLowerCase() === ctx.governor.toLowerCase()) {
      return { owner: 'governor', ownerAddress }
    } else if (ctx.deployer && ownerAddress.toLowerCase() === ctx.deployer.toLowerCase()) {
      return { owner: 'deployer', ownerAddress }
    }
    return { owner: 'other', ownerAddress }
  } catch {
    return { owner: 'unknown', ownerAddress: '' }
  }
}

/**
 * Get contract status line (read-only, no sync operations)
 *
 * Returns a formatted status line similar to sync output:
 * - ✓ = ok, △ = code changed, ◷ = pending upgrade, ○ = not deployed, ❌ = error
 * - 🔑 = ProxyAdmin still owned by deployer (not yet transferred to governor)
 *
 * @param client - Viem public client
 * @param addressBookType - Which address book this contract belongs to
 * @param addressBook - Address book instance
 * @param contractName - Name of the contract in the registry
 * @param metadata - Contract metadata from registry (optional, will look up if not provided)
 * @param ownershipCtx - Governor/deployer context for proxy admin ownership checks
 */
export async function getContractStatusLine(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  client: any,
  addressBookType: AddressBookType,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  addressBook: any,
  contractName: string,
  metadata?: ContractMetadata,
  ownershipCtx?: ProxyAdminOwnershipContext,
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

    // If no client available, show address book status without on-chain verification
    if (!client) {
      if (meta?.proxyType && entry.implementation) {
        return {
          line: `?   ${contractName} @ ${formatAddress(entry.address)} → ${formatAddress(entry.implementation)} (no on-chain check)`,
          exists: true,
        }
      }
      return { line: `?   ${contractName} @ ${formatAddress(entry.address)} (no on-chain check)`, exists: true }
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
        // Check code changes: own artifact first, then shared implementation's artifact
        let { codeChanged } = checkCodeChanged(meta.artifact, addressBook, entryName)
        if (!codeChanged && meta.sharedImplementation) {
          const sharedMeta = getContractMetadata(addressBookType, meta.sharedImplementation)
          if (sharedMeta?.artifact) {
            const sharedCheck = checkCodeChanged(sharedMeta.artifact, addressBook, meta.sharedImplementation)
            codeChanged = sharedCheck.codeChanged
          }
        }

        // Query proxy admin ownership for OZ v5 transparent proxies only
        // (old Graph proxies are controller-governed, owner() doesn't exist)
        let proxyAdminOwner: ProxyAdminOwner | undefined
        let proxyAdminOwnerAddress: string | undefined
        if (ownershipCtx && proxyAdminAddress && meta.proxyType !== 'graph') {
          const ownership = await queryProxyAdminOwnership(client, proxyAdminAddress, ownershipCtx)
          proxyAdminOwner = ownership.owner
          proxyAdminOwnerAddress = ownership.ownerAddress
        }

        const result = formatProxyStatusLine({
          name: contractName,
          proxyAddress: entry.address,
          implAddress: actualImpl,
          pendingAddress: entry.pendingImplementation?.address,
          codeChanged,
          proxyAdminOwner,
        })

        // Check if address book is stale (on-chain impl differs from recorded impl)
        const warnings: string[] = []
        const bookImpl = entry.implementation
        if (bookImpl && actualImpl.toLowerCase() !== bookImpl.toLowerCase()) {
          warnings.push(`address book stale: recorded impl ${formatAddress(bookImpl)}`)
        }

        return {
          line: result.line,
          exists: true,
          warnings: warnings.length > 0 ? warnings : undefined,
          proxyAdminOwner,
          proxyAdminAddress,
          proxyAdminOwnerAddress,
          codeChanged,
          hasPendingImplementation: !!entry.pendingImplementation?.address,
        }
      }
    }

    // Non-proxy contract — check for code changes against stored bytecodeHash
    const { codeChanged } = meta?.artifact
      ? checkCodeChanged(meta.artifact, addressBook, entryName)
      : { codeChanged: false }
    const icon = codeChanged ? '△' : '✓'
    return { line: `${icon}   ${contractName} @ ${formatAddress(entry.address)}`, exists: true, codeChanged }
  } catch (e) {
    const errMsg = e instanceof Error ? e.message.split('\n')[0].slice(0, 120) : String(e).slice(0, 120)
    return { line: `⚠   ${contractName}: error reading (${errMsg})`, exists: false }
  }
}

/**
 * Check if any deployable proxy across all address books has a pending
 * implementation or local code that differs from the deployed version.
 *
 * Used by status scripts for next-step guidance without duplicating
 * address book scanning logic.
 */
export function checkAllProxyStates(targetChainId: number): { anyCodeChanged: boolean; anyPending: boolean } {
  const addressBookTypes: AddressBookType[] = ['horizon', 'subgraph-service', 'issuance']
  let anyCodeChanged = false
  let anyPending = false

  for (const abType of addressBookTypes) {
    const ab: AnyAddressBookOps = getAddressBookForType(abType, targetChainId)

    for (const [name, meta] of getContractsByAddressBook(abType)) {
      if (!meta.deployable || !meta.proxyType) continue
      if (!ab.entryExists(name)) continue
      const entry = ab.getEntry(name)
      if (!entry?.address) continue

      if (entry.pendingImplementation?.address) anyPending = true
      if (meta.artifact) {
        const { codeChanged } = checkCodeChanged(meta.artifact, ab, name)
        if (codeChanged) anyCodeChanged = true
      } else if (meta.sharedImplementation) {
        const sharedMeta = getContractMetadata(abType, meta.sharedImplementation)
        if (sharedMeta?.artifact) {
          const { codeChanged } = checkCodeChanged(sharedMeta.artifact, ab, meta.sharedImplementation)
          if (codeChanged) anyCodeChanged = true
        }
      }

      if (anyCodeChanged && anyPending) return { anyCodeChanged, anyPending }
    }
  }

  return { anyCodeChanged, anyPending }
}
