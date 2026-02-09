import { spawn } from 'child_process'
import fs from 'fs'
import { configVariable, task } from 'hardhat/config'
import { ArgumentType } from 'hardhat/types/arguments'
import type { NewTaskActionFunction } from 'hardhat/types/tasks'
import os from 'os'
import path from 'path'
import { decodeAbiParameters } from 'viem'

import type { AnyAddressBookOps } from '../lib/address-book-ops.js'
import { computeBytecodeHash } from '../lib/bytecode-utils.js'
import {
  type AddressBookType,
  type ArtifactSource,
  type ContractMetadata,
  getContractMetadata,
  getContractsByAddressBook,
} from '../lib/contract-registry.js'
import { loadArtifactFromSource } from '../lib/deploy-implementation.js'
import { verifyOZProxy } from '../lib/oz-proxy-verify.js'
import { graph } from '../rocketh/deploy.js'

const ADDRESS_BOOK_TYPES: AddressBookType[] = ['horizon', 'subgraph-service', 'issuance']

/**
 * Map artifact source type to package directory
 */
function getPackageDir(artifactSource: ArtifactSource): string {
  switch (artifactSource.type) {
    case 'contracts':
      return 'packages/contracts'
    case 'subgraph-service':
      return 'packages/subgraph-service'
    case 'issuance':
      return 'packages/issuance'
    case 'openzeppelin':
      throw new Error('Cannot verify OpenZeppelin contracts directly')
  }
}

/**
 * Get fully qualified contract name for hardhat verify --contract flag
 * This ensures hardhat uses current build artifacts instead of Ignition deployment artifacts
 */
function getFullyQualifiedContractName(artifactSource: ArtifactSource): string {
  switch (artifactSource.type) {
    case 'contracts':
      // e.g., contracts/rewards/RewardsManager.sol:RewardsManager
      return `contracts/${artifactSource.path}/${artifactSource.name}.sol:${artifactSource.name}`
    case 'subgraph-service':
      // e.g., contracts/SubgraphService.sol:SubgraphService
      return `contracts/${artifactSource.name}.sol:${artifactSource.name}`
    case 'issuance': {
      // path is like 'contracts/allocate/IssuanceAllocator.sol/IssuanceAllocator'
      // Need to convert to 'contracts/allocate/IssuanceAllocator.sol:IssuanceAllocator'
      const parts = artifactSource.path.split('/')
      const contractName = parts.pop()!
      const solPath = parts.join('/')
      return `${solPath}:${contractName}`
    }
    case 'openzeppelin':
      throw new Error('Cannot verify OpenZeppelin contracts directly')
  }
}

/**
 * Find which address book contains a deployable contract
 * Returns undefined if not found, throws if ambiguous (found in multiple)
 */
function findContractAddressBook(
  contractName: string,
): { addressBook: AddressBookType; metadata: ContractMetadata } | undefined {
  const matches: Array<{ addressBook: AddressBookType; metadata: ContractMetadata }> = []

  for (const addressBook of ADDRESS_BOOK_TYPES) {
    const metadata = getContractMetadata(addressBook, contractName)
    // Only consider entries that are deployable and have an artifact source
    if (metadata?.deployable && metadata.artifact) {
      matches.push({ addressBook, metadata })
    }
  }

  if (matches.length === 0) {
    return undefined
  }

  if (matches.length > 1) {
    const books = matches.map((m) => m.addressBook).join(', ')
    throw new Error(
      `Contract ${contractName} found as deployable in multiple address books: ${books}\n` +
        `Use --address-book to specify which one to use.`,
    )
  }

  return matches[0]
}

/**
 * Get all deployable contracts across all address books
 */
function getAllDeployableContracts(): Array<{
  name: string
  addressBook: AddressBookType
  metadata: ContractMetadata
}> {
  const contracts: Array<{ name: string; addressBook: AddressBookType; metadata: ContractMetadata }> = []

  for (const addressBook of ADDRESS_BOOK_TYPES) {
    for (const [name, metadata] of getContractsByAddressBook(addressBook)) {
      if (metadata.deployable && metadata.artifact) {
        contracts.push({ name, addressBook, metadata })
      }
    }
  }

  return contracts
}

/**
 * Resolve a configuration variable using Hardhat's hook chain (keystore + env fallback)
 */
async function resolveConfigVar(hre: unknown, name: string): Promise<string | undefined> {
  try {
    const variable = configVariable(name)
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const hooks = (hre as any).hooks

    const value = await hooks.runHandlerChain(
      'configurationVariables',
      'fetchValue',
      [variable],
      async (_context: unknown, v: { name: string }) => {
        const envValue = process.env[v.name]
        if (typeof envValue !== 'string') {
          throw new Error(`Environment variable ${v.name} not found`)
        }
        return envValue
      },
    )
    return value
  } catch {
    return undefined
  }
}

/**
 * Check if a package uses Hardhat v3 (which has different verify CLI options)
 */
function isHardhatV3Package(artifactSource: ArtifactSource): boolean {
  // issuance uses HH v3, others use HH v2
  return artifactSource.type === 'issuance'
}

/**
 * Decode ABI-encoded constructor args using the contract ABI
 * Returns array of decoded values suitable for HH v3 verify
 */
function decodeConstructorArgs(artifact: { abi: readonly unknown[] }, argsData: string): unknown[] | undefined {
  if (!argsData || argsData === '0x') return undefined

  // Find constructor in ABI
  const constructorAbi = artifact.abi.find((item: unknown) => (item as { type?: string }).type === 'constructor') as
    | { inputs?: Array<{ type: string; name: string }> }
    | undefined

  if (!constructorAbi?.inputs?.length) return undefined

  try {
    // Decode using viem
    const decoded = decodeAbiParameters(
      constructorAbi.inputs.map((input) => ({
        type: input.type,
        name: input.name,
      })),
      argsData as `0x${string}`,
    )
    return [...decoded]
  } catch {
    return undefined
  }
}

/**
 * Create a temp file with constructor args for HH v3 verify
 * Returns the path to the temp file, or undefined if no args
 */
function createConstructorArgsFile(decodedArgs: unknown[]): string {
  const tempDir = os.tmpdir()
  const tempFile = path.join(tempDir, `constructor-args-${Date.now()}.cjs`)

  // Format args for JS module export
  const formattedArgs = decodedArgs.map((arg) => {
    if (typeof arg === 'bigint') {
      return `"${arg.toString()}"`
    }
    if (typeof arg === 'string') {
      return `"${arg}"`
    }
    return JSON.stringify(arg)
  })

  const content = `module.exports = [${formattedArgs.join(', ')}];\n`
  fs.writeFileSync(tempFile, content)
  return tempFile
}

/**
 * Run hardhat verify in a child process with the given environment
 * Returns true if verification succeeded, false if it failed (but doesn't throw)
 */
async function runVerify(
  packageDir: string,
  network: string,
  address: string,
  apiKey: string,
  constructorArgsData?: string,
  artifact?: { abi: readonly unknown[] },
  isHHv3?: boolean,
  fullyQualifiedName?: string,
): Promise<{ success: boolean; url?: string }> {
  const repoRoot = path.resolve(process.cwd(), '../..')
  const cwd = path.resolve(repoRoot, packageDir)

  // Build verify command (API key passed via env vars)
  // Use --contract to explicitly specify which contract to verify,
  // ensuring hardhat uses current build artifacts instead of Ignition deployment artifacts
  const args = ['hardhat', 'verify', '--network', network]
  if (fullyQualifiedName) {
    args.push('--contract', fullyQualifiedName)
  }
  args.push(address)

  let tempArgsFile: string | undefined

  // Handle constructor args - both HH v2 and v3 use temp file, different flag names
  if (constructorArgsData && constructorArgsData !== '0x' && artifact) {
    const decodedArgs = decodeConstructorArgs(artifact, constructorArgsData)
    if (decodedArgs?.length) {
      tempArgsFile = createConstructorArgsFile(decodedArgs)
      // HH v2: --constructor-args, HH v3: --constructor-args-path
      const argsFlag = isHHv3 ? '--constructor-args-path' : '--constructor-args'
      args.push(argsFlag, tempArgsFile)
    }
  }

  console.log(`    📂 Package: ${packageDir}`)
  const hasArgs = constructorArgsData && constructorArgsData !== '0x'
  const argsDisplay = isHHv3 ? '--constructor-args-path ...' : '--constructor-args ...'
  const contractFlag = fullyQualifiedName ? ` --contract ${fullyQualifiedName}` : ''
  console.log(
    `    🔧 Command: npx hardhat verify --network ${network}${contractFlag} ${address}${hasArgs ? ` ${argsDisplay}` : ''}`,
  )

  return new Promise((resolve) => {
    let output = ''

    const child = spawn('npx', args, {
      cwd,
      env: {
        ...process.env,
        // Pass API key via env vars (hardhat-verify reads from these)
        ARBISCAN_API_KEY: apiKey,
        ETHERSCAN_API_KEY: apiKey,
      },
      stdio: ['inherit', 'pipe', 'pipe'],
    })

    // Capture and display output
    child.stdout?.on('data', (data) => {
      const text = data.toString()
      output += text
      process.stdout.write(text)
    })

    child.stderr?.on('data', (data) => {
      const text = data.toString()
      output += text
      process.stderr.write(text)
    })

    child.on('close', (code) => {
      // Clean up temp file if created
      if (tempArgsFile) {
        try {
          fs.unlinkSync(tempArgsFile)
        } catch {
          // Ignore cleanup errors
        }
      }

      // Extract verification URL from output (matches arbiscan/etherscan URLs)
      const urlMatch = output.match(/https:\/\/[^\s]*(?:arbiscan|etherscan)[^\s]*\/address\/[^\s#]*#code/)
      resolve({ success: code === 0, url: urlMatch?.[0] })
    })

    child.on('error', () => {
      // Clean up temp file if created
      if (tempArgsFile) {
        try {
          fs.unlinkSync(tempArgsFile)
        } catch {
          // Ignore cleanup errors
        }
      }
      resolve({ success: false })
    })
  })
}

/**
 * Get address book for a given type and chainId
 */
function getAddressBook(addressBookType: AddressBookType, chainId: number): AnyAddressBookOps {
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
 * Check if local artifact bytecode matches stored bytecodeHash
 *
 * Uses the bytecodeHash stored in address book to verify local artifact
 * hasn't changed since deployment. This avoids unreliable on-chain bytecode
 * comparison with immutable masking.
 */
function checkBytecodeMatch(
  contractName: string,
  metadata: ContractMetadata,
  addressBook: AnyAddressBookOps,
): { matches: boolean; reason?: string } {
  try {
    const artifact = loadArtifactFromSource(metadata.artifact!)
    if (!artifact.deployedBytecode) {
      return { matches: false, reason: 'no artifact bytecode' }
    }

    // Get stored bytecodeHash from address book
    const deploymentMetadata = addressBook.getDeploymentMetadata(contractName)
    if (!deploymentMetadata?.bytecodeHash) {
      // No stored bytecodeHash - can't verify code matches what was deployed
      // Skip verification (contract was not deployed by this system or is legacy)
      return { matches: false, reason: 'no deployment metadata (not deployed by this system)' }
    }

    // Compare local artifact bytecodeHash with stored hash
    const localBytecodeHash = computeBytecodeHash(artifact.deployedBytecode)
    if (localBytecodeHash !== deploymentMetadata.bytecodeHash) {
      return {
        matches: false,
        reason: `bytecode hash mismatch - local artifact differs from deployed`,
      }
    }

    return { matches: true }
  } catch (error) {
    return { matches: false, reason: `error checking bytecode: ${(error as Error).message}` }
  }
}

interface VerifyResult {
  contract: string
  addressBook: AddressBookType
  status: 'verified' | 'skipped' | 'failed'
  reason?: string
}

/**
 * Verify a single contract
 */
async function verifySingleContract(
  networkName: string,
  chainId: number,
  contractName: string,
  addressBookType: AddressBookType,
  metadata: ContractMetadata,
  apiKey: string,
  proxyOnly: boolean,
  implOnly: boolean,
): Promise<VerifyResult> {
  const addressBook = getAddressBook(addressBookType, chainId)

  // Check if deployed
  if (!addressBook.entryExists(contractName)) {
    return { contract: contractName, addressBook: addressBookType, status: 'skipped', reason: 'not deployed' }
  }

  const entry = addressBook.getEntry(contractName)
  const isProxied = Boolean(metadata.proxyType)
  const implAddress = isProxied ? entry.implementation : entry.address

  // Check bytecode matches for implementation (using stored bytecodeHash)
  if (implAddress) {
    const bytecodeCheck = checkBytecodeMatch(contractName, metadata, addressBook)
    if (!bytecodeCheck.matches) {
      return {
        contract: contractName,
        addressBook: addressBookType,
        status: 'skipped',
        reason: bytecodeCheck.reason,
      }
    }
  }

  const packageDir = getPackageDir(metadata.artifact!)
  const isHHv3 = isHardhatV3Package(metadata.artifact!)
  const artifact = loadArtifactFromSource(metadata.artifact!)
  const fullyQualifiedName = getFullyQualifiedContractName(metadata.artifact!)
  let implResult: { success: boolean; url?: string } = { success: true }

  // Get constructor args from deployment metadata
  const deploymentMetadata = addressBook.getDeploymentMetadata?.(contractName)
  const constructorArgsData = deploymentMetadata?.argsData

  // Verify proxy (if proxied and not impl-only)
  // OZ TransparentUpgradeableProxy verification uses direct Etherscan API with Standard JSON Input
  if (isProxied && !implOnly) {
    // Skip if already verified
    if (entry.proxyDeployment?.verified) {
      console.log(`  ✓ Proxy already verified: ${entry.proxyDeployment.verified}`)
    } else {
      // Get proxy constructor args from address book (stored separately from implementation args)
      const proxyArgsData = entry.proxyDeployment?.argsData
      if (!proxyArgsData) {
        console.log(`  ⏭️  Proxy verification skipped (no constructor args in address book)`)
      } else {
        console.log(`  📋 Verifying OZ TransparentUpgradeableProxy at: ${entry.address}`)
        console.log(`    📦 Source: @openzeppelin/contracts v5.4.0 (from node_modules)`)

        const proxyResult = await verifyOZProxy(entry.address, proxyArgsData, apiKey, chainId)

        if (proxyResult.success && proxyResult.url) {
          console.log(`    ✅ Proxy verification complete`)
          // Record verification URL in address book (setVerified sets proxyDeployment.verified for proxied contracts)
          addressBook.setVerified(contractName, proxyResult.url)
        } else if (proxyResult.success) {
          console.log(`    ✅ Proxy verification complete (${proxyResult.message || 'no URL returned'})`)
        } else {
          console.log(`    ⚠️  Proxy verification failed: ${proxyResult.message || 'unknown error'}`)
        }
      }
    }
  }

  // Verify implementation (if proxied and not proxy-only, or if not proxied)
  if ((isProxied && !proxyOnly) || !isProxied) {
    if (!implAddress) {
      console.log('  ⚠️  No implementation address found, skipping')
    } else {
      // Skip if already verified
      const implVerified = isProxied ? entry.implementationDeployment?.verified : entry.deployment?.verified
      if (implVerified) {
        const label = isProxied ? 'Implementation' : 'Contract'
        console.log(`  ✓ ${label} already verified: ${implVerified}`)
      } else {
        const label = isProxied ? 'implementation' : 'contract'
        console.log(`  📋 Verifying ${label} at: ${implAddress}`)
        // Pass constructor args for implementation contracts
        // Use fullyQualifiedName to ensure hardhat uses current build artifacts
        implResult = await runVerify(
          packageDir,
          networkName,
          implAddress,
          apiKey,
          constructorArgsData,
          artifact,
          isHHv3,
          fullyQualifiedName,
        )
        if (implResult.success && implResult.url) {
          console.log(`    ✅ ${label.charAt(0).toUpperCase() + label.slice(1)} verification complete`)
          // Record verification URL in address book
          if (isProxied) {
            addressBook.setImplementationVerified(contractName, implResult.url)
          } else {
            addressBook.setVerified(contractName, implResult.url)
          }
        } else if (implResult.success) {
          console.log(`    ✅ ${label.charAt(0).toUpperCase() + label.slice(1)} verification complete`)
        } else {
          console.log(
            `    ⚠️  ${label.charAt(0).toUpperCase() + label.slice(1)} verification failed (may already be verified)`,
          )
        }
      }
    }
  }

  // Both failing or already verified is still "success" for the workflow
  return { contract: contractName, addressBook: addressBookType, status: 'verified' }
}

interface TaskArgs {
  contract: string
  addressBook: string
  proxyOnly: boolean
  implOnly: boolean
}

/**
 * Verify deployed contracts on Etherscan/Arbiscan
 *
 * This task automates verification by:
 * 1. Finding all deployable contracts (or a specific one if --contract is provided)
 * 2. Checking if each contract is deployed and bytecode matches
 * 3. Running `npx hardhat verify` in the correct source package
 *
 * By default, verifies ALL deployable contracts. Contracts with bytecode mismatch
 * (out-of-date) are skipped with a warning.
 *
 * Usage:
 *   npx hardhat deploy:verify --network arbitrumSepolia                    # verify all
 *   npx hardhat deploy:verify --contract RewardsManager --network arbitrumSepolia  # verify one
 *   npx hardhat deploy:verify --impl-only --network arbitrumSepolia        # implementations only
 */
const action: NewTaskActionFunction<TaskArgs> = async (taskArgs, hre) => {
  const { contract, proxyOnly, implOnly } = taskArgs
  const explicitAddressBook = taskArgs.addressBook || undefined

  if (proxyOnly && implOnly) {
    throw new Error('Cannot specify both --proxy-only and --impl-only')
  }

  // HH v3: Connect to network
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const conn = await (hre as any).network.connect()
  const networkName = conn.networkName
  const chainId = await conn.provider.request({ method: 'eth_chainId' }).then((hex: string) => parseInt(hex, 16))

  // Get API key from keystore
  const apiKey = await resolveConfigVar(hre, 'ARBISCAN_API_KEY')
  if (!apiKey) {
    throw new Error('ARBISCAN_API_KEY not found. Set it in keystore:\n  npx hardhat keystore set ARBISCAN_API_KEY')
  }

  // Determine contracts to verify
  let contractsToVerify: Array<{ name: string; addressBook: AddressBookType; metadata: ContractMetadata }>

  if (contract) {
    // Single contract mode
    let addressBookType: AddressBookType
    let metadata: ContractMetadata

    if (explicitAddressBook) {
      addressBookType = explicitAddressBook as AddressBookType
      const foundMetadata = getContractMetadata(addressBookType, contract)
      if (!foundMetadata?.deployable || !foundMetadata.artifact) {
        throw new Error(`Contract ${contract} not found as deployable in ${addressBookType} registry`)
      }
      metadata = foundMetadata
    } else {
      const found = findContractAddressBook(contract)
      if (!found) {
        throw new Error(`Contract ${contract} not found as deployable in any address book`)
      }
      addressBookType = found.addressBook
      metadata = found.metadata
    }

    contractsToVerify = [{ name: contract, addressBook: addressBookType, metadata }]
    console.log(`\n🔍 Verifying ${contract} on ${networkName} (chainId: ${chainId})`)
  } else {
    // All contracts mode
    contractsToVerify = getAllDeployableContracts()
    console.log(`\n🔍 Verifying all deployable contracts on ${networkName} (chainId: ${chainId})`)
    console.log(`   Found ${contractsToVerify.length} deployable contracts`)
  }

  // Verify each contract
  const results: VerifyResult[] = []

  for (const { name, addressBook, metadata } of contractsToVerify) {
    console.log(`\n📦 ${name} (${addressBook})`)

    const result = await verifySingleContract(
      networkName,
      chainId,
      name,
      addressBook,
      metadata,
      apiKey,
      proxyOnly,
      implOnly,
    )

    results.push(result)

    if (result.status === 'skipped') {
      console.log(`  ⏭️  Skipped: ${result.reason}`)
    }
  }

  // Summary
  console.log('\n' + '═'.repeat(50))
  console.log('📊 Verification Summary')
  console.log('═'.repeat(50))

  const verified = results.filter((r) => r.status === 'verified')
  const skipped = results.filter((r) => r.status === 'skipped')
  const failed = results.filter((r) => r.status === 'failed')

  console.log(`✅ Verified: ${verified.length}`)
  if (verified.length > 0) {
    for (const r of verified) {
      console.log(`   - ${r.contract}`)
    }
  }

  if (skipped.length > 0) {
    console.log(`⏭️  Skipped: ${skipped.length}`)
    for (const r of skipped) {
      console.log(`   - ${r.contract}: ${r.reason}`)
    }
  }

  if (failed.length > 0) {
    console.log(`❌ Failed: ${failed.length}`)
    for (const r of failed) {
      console.log(`   - ${r.contract}: ${r.reason}`)
    }
  }
}

const verifyContractTask = task('deploy:verify', 'Verify deployed contracts on Etherscan/Arbiscan')
  .addOption({
    name: 'contract',
    description: 'Contract name to verify (verifies all if not specified)',
    type: ArgumentType.STRING,
    defaultValue: '',
  })
  .addOption({
    name: 'addressBook',
    description: 'Address book to use (auto-detected if not specified)',
    type: ArgumentType.STRING,
    defaultValue: '',
  })
  .addOption({
    name: 'proxyOnly',
    description: 'Only verify proxy addresses (skip implementations)',
    type: ArgumentType.FLAG,
    defaultValue: false,
  })
  .addOption({
    name: 'implOnly',
    description: 'Only verify implementation addresses (skip proxies)',
    type: ArgumentType.FLAG,
    defaultValue: false,
  })
  .setAction(async () => ({ default: action }))
  .build()

export default verifyContractTask
