/**
 * Pre-flight validation for deployment records
 *
 * Validates that deployment records can be reconstructed and are consistent
 * with on-chain state. Run before deployments to catch issues early.
 */

import type { DeploymentMetadata } from '@graphprotocol/toolshed/deployments'

import type { AnyAddressBookOps } from './address-book-ops.js'
import type { ArtifactSource } from './contract-registry.js'
import { computeBytecodeHash } from './bytecode-utils.js'
import {
  loadContractsArtifact,
  loadIssuanceArtifact,
  loadOpenZeppelinArtifact,
  loadSubgraphServiceArtifact,
} from './artifact-loaders.js'

/**
 * Result of validating a single contract
 */
export interface ValidationResult {
  /** Contract name */
  contract: string
  /** Validation status */
  status: 'valid' | 'warning' | 'error'
  /** Human-readable message */
  message: string
  /** Additional details for debugging */
  details?: Record<string, unknown>
}

/**
 * Options for validation
 */
export interface ValidationOptions {
  /** Whether to perform on-chain checks (requires provider) */
  checkOnChain?: boolean
  /** Whether to verify argsData matches transaction input */
  verifyArgsData?: boolean
}

/**
 * Load artifact from source type
 */
function loadArtifact(source: ArtifactSource) {
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
}

/**
 * Validate deployment metadata is complete
 */
function validateMetadataComplete(metadata: DeploymentMetadata | undefined): {
  valid: boolean
  missing: string[]
} {
  if (!metadata) {
    return { valid: false, missing: ['all fields'] }
  }

  const missing: string[] = []
  if (!metadata.txHash) missing.push('txHash')
  if (!metadata.argsData) missing.push('argsData')
  if (!metadata.bytecodeHash) missing.push('bytecodeHash')

  return { valid: missing.length === 0, missing }
}

/**
 * Validate a single contract's deployment record
 *
 * Checks:
 * 1. Entry exists in address book
 * 2. Deployment metadata exists and is complete
 * 3. Bytecode hash matches local artifact
 * 4. (Optional) Address has code on-chain
 * 5. (Optional) argsData matches transaction input
 */
export async function validateContract(
  addressBook: AnyAddressBookOps,
  contractName: string,
  artifact: ArtifactSource,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  client?: any,
  options: ValidationOptions = {},
): Promise<ValidationResult> {
  // Check if entry exists
  if (!addressBook.entryExists(contractName)) {
    return {
      contract: contractName,
      status: 'valid',
      message: 'not deployed (no entry)',
    }
  }

  const entry = addressBook.getEntry(contractName)

  // Check if address is valid
  if (!entry.address || entry.address === '0x0000000000000000000000000000000000000000') {
    return {
      contract: contractName,
      status: 'valid',
      message: 'not deployed (zero address)',
    }
  }

  // Check deployment metadata
  const metadata = addressBook.getDeploymentMetadata(contractName)
  const metadataCheck = validateMetadataComplete(metadata)

  if (!metadataCheck.valid) {
    return {
      contract: contractName,
      status: 'warning',
      message: `missing deployment metadata: ${metadataCheck.missing.join(', ')}`,
      details: { address: entry.address, missingFields: metadataCheck.missing },
    }
  }

  // Load artifact and verify bytecode hash
  let loadedArtifact
  try {
    loadedArtifact = loadArtifact(artifact)
  } catch {
    return {
      contract: contractName,
      status: 'warning',
      message: 'could not load artifact for bytecode comparison',
      details: { artifactSource: artifact },
    }
  }

  if (loadedArtifact?.deployedBytecode && metadata?.bytecodeHash) {
    const localHash = computeBytecodeHash(loadedArtifact.deployedBytecode)
    if (metadata.bytecodeHash !== localHash) {
      return {
        contract: contractName,
        status: 'warning',
        message: 'local bytecode differs from deployed version',
        details: {
          address: entry.address,
          storedHash: metadata.bytecodeHash,
          localHash,
        },
      }
    }
  }

  // Optional: Check on-chain state
  if (options.checkOnChain && client) {
    try {
      const code = await client.getCode({ address: entry.address as `0x${string}` })
      if (!code || code === '0x') {
        return {
          contract: contractName,
          status: 'error',
          message: 'no code at address on-chain',
          details: { address: entry.address },
        }
      }
    } catch (error) {
      return {
        contract: contractName,
        status: 'error',
        message: `failed to check on-chain code: ${(error as Error).message}`,
        details: { address: entry.address },
      }
    }

    // Optional: Verify argsData matches transaction
    if (options.verifyArgsData && metadata?.txHash && loadedArtifact?.bytecode) {
      try {
        const tx = await client.getTransaction({ hash: metadata.txHash as `0x${string}` })
        if (tx?.input) {
          // Extract args from tx input (after bytecode)
          const bytecodeLength = loadedArtifact.bytecode.length
          const extractedArgs = '0x' + tx.input.slice(bytecodeLength)

          if (extractedArgs.toLowerCase() !== metadata.argsData.toLowerCase()) {
            return {
              contract: contractName,
              status: 'error',
              message: 'argsData mismatch with deployment transaction',
              details: {
                txHash: metadata.txHash,
                storedArgs: metadata.argsData,
                extractedArgs,
              },
            }
          }
        }
      } catch {
        // Transaction lookup failed - not a critical error
      }
    }
  }

  return {
    contract: contractName,
    status: 'valid',
    message: 'ok',
    details: {
      address: entry.address,
      hasMetadata: true,
      bytecodeHashMatches: true,
    },
  }
}

/**
 * Validate multiple contracts
 *
 * @param addressBook - Address book ops instance
 * @param contracts - List of contracts with their artifact sources
 * @param client - Optional viem client for on-chain checks
 * @param options - Validation options
 */
export async function validateContracts(
  addressBook: AnyAddressBookOps,
  contracts: Array<{ name: string; artifact: ArtifactSource }>,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  client?: any,
  options: ValidationOptions = {},
): Promise<ValidationResult[]> {
  const results: ValidationResult[] = []

  for (const { name, artifact } of contracts) {
    const result = await validateContract(addressBook, name, artifact, client, options)
    results.push(result)
  }

  return results
}

/**
 * Summary of validation results
 */
export interface ValidationSummary {
  /** Total contracts checked */
  total: number
  /** Contracts with valid status */
  valid: number
  /** Contracts with warnings */
  warnings: number
  /** Contracts with errors */
  errors: number
  /** Whether all checks passed (no errors) */
  success: boolean
  /** Individual results */
  results: ValidationResult[]
}

/**
 * Summarize validation results
 */
export function summarizeValidation(results: ValidationResult[]): ValidationSummary {
  const summary: ValidationSummary = {
    total: results.length,
    valid: 0,
    warnings: 0,
    errors: 0,
    success: true,
    results,
  }

  for (const result of results) {
    switch (result.status) {
      case 'valid':
        summary.valid++
        break
      case 'warning':
        summary.warnings++
        break
      case 'error':
        summary.errors++
        summary.success = false
        break
    }
  }

  return summary
}

/**
 * Format validation results for display
 */
export function formatValidationResults(results: ValidationResult[]): string[] {
  const lines: string[] = []

  for (const result of results) {
    const icon = result.status === 'valid' ? '✓' : result.status === 'warning' ? '⚠' : '❌'
    lines.push(`${icon} ${result.contract}: ${result.message}`)
  }

  return lines
}
