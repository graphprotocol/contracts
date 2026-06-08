import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'

import type { Artifact } from '@rocketh/core/types'

import type { LibraryArtifactResolver, LinkReferences } from './bytecode-utils.js'

// Create require for JSON imports in ESM
const require = createRequire(import.meta.url)

/**
 * Load artifact from @graphprotocol/contracts package
 *
 * @param contractPath - Path within contracts/ (e.g., 'rewards', 'l2/token')
 * @param contractName - Contract name (e.g., 'RewardsManager', 'L2GraphToken')
 */
export function loadContractsArtifact(contractPath: string, contractName: string): Artifact {
  const artifactPath = require.resolve(
    `@graphprotocol/contracts/artifacts/contracts/${contractPath}/${contractName}.sol/${contractName}.json`,
  )
  const artifact = JSON.parse(readFileSync(artifactPath, 'utf-8'))
  return {
    abi: artifact.abi,
    bytecode: artifact.bytecode as `0x${string}`,
    deployedBytecode: artifact.deployedBytecode as `0x${string}`,
    metadata: artifact.metadata || '',
  }
}

/**
 * Load artifact from @graphprotocol/subgraph-service package (Hardhat format)
 *
 * @param contractName - Contract name (e.g., 'SubgraphService')
 */
export function loadSubgraphServiceArtifact(contractName: string): Artifact {
  // Support subdirectory names like 'libraries/IndexingAgreement'
  const baseName = contractName.includes('/') ? contractName.split('/').pop()! : contractName
  const artifactPath = require.resolve(
    `@graphprotocol/subgraph-service/artifacts/contracts/${contractName}.sol/${baseName}.json`,
  )
  const artifact = JSON.parse(readFileSync(artifactPath, 'utf-8'))

  return {
    abi: artifact.abi,
    bytecode: artifact.bytecode as `0x${string}`,
    deployedBytecode: artifact.deployedBytecode as `0x${string}`,
    metadata: artifact.metadata || '',
    linkReferences: artifact.linkReferences,
    deployedLinkReferences: artifact.deployedLinkReferences,
  }
}

/**
 * Load artifact from @graphprotocol/issuance package
 *
 * @param artifactSubpath - Path within artifacts/ (e.g., 'contracts/allocate/IssuanceAllocator.sol/IssuanceAllocator')
 */
export function loadIssuanceArtifact(artifactSubpath: string): Artifact {
  const artifactPath = require.resolve(`@graphprotocol/issuance/artifacts/${artifactSubpath}.json`)
  const artifact = JSON.parse(readFileSync(artifactPath, 'utf-8'))
  return {
    abi: artifact.abi,
    bytecode: artifact.bytecode as `0x${string}`,
    deployedBytecode: artifact.deployedBytecode as `0x${string}`,
    metadata: artifact.metadata || '',
    linkReferences: artifact.linkReferences,
    deployedLinkReferences: artifact.deployedLinkReferences,
  }
}

/**
 * Load artifact from @graphprotocol/horizon package build directory
 *
 * @param artifactSubpath - Path within build/contracts/ (e.g., '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol/ProxyAdmin')
 */
export function loadHorizonBuildArtifact(artifactSubpath: string): Artifact {
  const artifactPath = require.resolve(`@graphprotocol/horizon/artifacts/${artifactSubpath}.json`)
  const artifact = JSON.parse(readFileSync(artifactPath, 'utf-8'))
  return {
    abi: artifact.abi,
    bytecode: artifact.bytecode as `0x${string}`,
    deployedBytecode: artifact.deployedBytecode as `0x${string}`,
    metadata: artifact.metadata || '',
    linkReferences: artifact.linkReferences,
    deployedLinkReferences: artifact.deployedLinkReferences,
  }
}

/**
 * Load artifact from @openzeppelin/contracts package build directory
 *
 * @param contractName - Contract name (e.g., 'ProxyAdmin', 'AccessControl')
 */
export function loadOpenZeppelinArtifact(contractName: string): Artifact {
  const artifactPath = require.resolve(`@openzeppelin/contracts/build/contracts/${contractName}.json`)
  const artifact = JSON.parse(readFileSync(artifactPath, 'utf-8'))
  return {
    abi: artifact.abi,
    bytecode: artifact.bytecode as `0x${string}`,
    deployedBytecode: artifact.deployedBytecode as `0x${string}`,
    metadata: artifact.metadata || '',
  }
}

/**
 * Create a library artifact resolver for a given package.
 *
 * Library artifacts live at <package>/artifacts/<sourcePath>/<name>.json,
 * mirroring the linkReferences source paths from Hardhat compilation.
 */
function createPackageLibraryResolver(packagePrefix: string): LibraryArtifactResolver {
  return (sourcePath: string, libraryName: string) => {
    try {
      const libPath = require.resolve(`${packagePrefix}/${sourcePath}/${libraryName}.json`)
      const artifact = JSON.parse(readFileSync(libPath, 'utf-8'))
      return {
        deployedBytecode: artifact.deployedBytecode as string,
        deployedLinkReferences: artifact.deployedLinkReferences as LinkReferences | undefined,
      }
    } catch {
      return undefined
    }
  }
}

/**
 * Get a library artifact resolver for the given artifact source type.
 * Returns undefined if the source type doesn't support library resolution.
 */
export function getLibraryResolver(sourceType: string): LibraryArtifactResolver | undefined {
  switch (sourceType) {
    case 'subgraph-service':
      return createPackageLibraryResolver('@graphprotocol/subgraph-service/artifacts')
    case 'horizon':
      return createPackageLibraryResolver('@graphprotocol/horizon/artifacts')
    case 'issuance':
      return createPackageLibraryResolver('@graphprotocol/issuance/artifacts')
    case 'contracts':
      return createPackageLibraryResolver('@graphprotocol/contracts/artifacts')
    default:
      return undefined
  }
}

/**
 * Pre-link library addresses into an artifact's creation bytecode.
 *
 * Rocketh's deploy() stores the artifact's bytecode verbatim but compares
 * against linked bytecode on subsequent runs. For artifacts with library
 * references this causes a permanent mismatch (unlinked placeholders vs
 * resolved addresses), triggering a redeploy every time.
 *
 * Call this before passing the artifact to rocketh's deploy(). The returned
 * artifact has fully resolved bytecode and cleared linkReferences, so
 * rocketh stores what it will compare against next run.
 *
 * @param artifact - Artifact with unlinked bytecode and linkReferences
 * @param libraries - Map of library name → deployed address
 */
export function linkArtifactLibraries(artifact: Artifact, libraries: Record<string, `0x${string}`>): Artifact {
  let bytecode = artifact.bytecode as string

  if (artifact.linkReferences) {
    for (const [, fileReferences] of Object.entries(
      artifact.linkReferences as Record<string, Record<string, Array<{ start: number; length: number }>>>,
    )) {
      for (const [libName, fixups] of Object.entries(fileReferences)) {
        const addr = libraries[libName]
        if (!addr) continue
        for (const fixup of fixups) {
          bytecode =
            bytecode.substring(0, 2 + fixup.start * 2) +
            addr.substring(2) +
            bytecode.substring(2 + (fixup.start + fixup.length) * 2)
        }
      }
    }
  }

  return {
    ...artifact,
    bytecode: bytecode as `0x${string}`,
    linkReferences: undefined,
  }
}

/**
 * Load OpenZeppelin TransparentUpgradeableProxy artifact (v5)
 */
export function loadTransparentProxyArtifact(): Artifact {
  return loadOpenZeppelinArtifact('TransparentUpgradeableProxy')
}

// Convenience functions for common issuance contracts

/**
 * Load IssuanceAllocator artifact
 */
export function loadIssuanceAllocatorArtifact(): Artifact {
  return loadIssuanceArtifact('contracts/allocate/IssuanceAllocator.sol/IssuanceAllocator')
}

/**
 * Load DirectAllocation artifact
 */
export function loadDirectAllocationArtifact(): Artifact {
  return loadIssuanceArtifact('contracts/allocate/DirectAllocation.sol/DirectAllocation')
}

/**
 * Load RewardsEligibilityOracle artifact
 */
export function loadRewardsEligibilityOracleArtifact(): Artifact {
  return loadIssuanceArtifact('contracts/eligibility/RewardsEligibilityOracle.sol/RewardsEligibilityOracle')
}
