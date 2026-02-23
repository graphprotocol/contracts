import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'

import type { Artifact } from '@rocketh/core/types'

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
  const artifactPath = require.resolve(
    `@graphprotocol/subgraph-service/artifacts/contracts/${contractName}.sol/${contractName}.json`,
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
  }
}

/**
 * Load artifact from @graphprotocol/horizon package build directory
 *
 * @param artifactSubpath - Path within build/contracts/ (e.g., '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol/ProxyAdmin')
 */
export function loadHorizonBuildArtifact(artifactSubpath: string): Artifact {
  const artifactPath = require.resolve(`@graphprotocol/horizon/build/contracts/${artifactSubpath}.json`)
  const artifact = JSON.parse(readFileSync(artifactPath, 'utf-8'))
  return {
    abi: artifact.abi,
    bytecode: artifact.bytecode as `0x${string}`,
    deployedBytecode: artifact.deployedBytecode as `0x${string}`,
    metadata: artifact.metadata || '',
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
