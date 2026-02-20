import type { DeploymentMetadata } from '@graphprotocol/toolshed/deployments'
import type { Environment } from '@rocketh/core/types'
import type { PublicClient } from 'viem'
import { encodeFunctionData } from 'viem'

import { Contracts, type RegistryEntry } from './contract-registry.js'
import { getGovernor } from './controller-utils.js'
import {
  deployImplementation,
  getImplementationConfig,
  getOnChainImplementation,
  loadArtifactFromSource,
} from './deploy-implementation.js'
import { loadTransparentProxyArtifact } from './artifact-loaders.js'
import { INITIALIZE_GOVERNOR_ABI } from './abis.js'
import { computeBytecodeHash } from './bytecode-utils.js'
import { deploy, graph } from '../rocketh/deploy.js'

/** ERC1967 admin slot: keccak256("eip1967.proxy.admin") - 1 */
const ERC1967_ADMIN_SLOT = '0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103'

/**
 * Require deployer account to be configured
 *
 * Standard pattern for checking deployer account exists in namedAccounts.
 * Throws an error if deployer is not configured.
 *
 * @param env - Deployment environment
 * @returns The deployer address
 */
export function requireDeployer(env: Environment): string {
  const deployer = env.namedAccounts.deployer
  if (!deployer) {
    throw new Error('No deployer account configured')
  }
  return deployer
}

/**
 * Require a contract deployment to exist, throwing a helpful error if not found
 */
export function requireContract(env: Environment, contract: RegistryEntry) {
  const deployment = env.getOrNull(contract.name)
  if (!deployment) {
    throw new Error(`${contract.name} not deployed. Run required deploy tags first.`)
  }
  return deployment
}

/**
 * Require L2GraphToken from deployments (synced from Horizon address book)
 * Provides specific error message about running sync
 */
export function requireGraphToken(env: Environment) {
  const deployment = env.getOrNull(Contracts.horizon.L2GraphToken.name)
  if (!deployment) {
    throw new Error(
      `Missing deployments/${env.name}/${Contracts.horizon.L2GraphToken.name}.json. ` +
        `Run sync to import ${Contracts.horizon.L2GraphToken.name} address from Horizon address book.`,
    )
  }
  return deployment
}

/**
 * Require multiple contract deployments to exist
 * Lists all missing contracts in error message
 */
export function requireContracts(env: Environment, contracts: RegistryEntry[]) {
  const missing: string[] = []
  const deployments = contracts.map((c) => {
    const deployment = env.getOrNull(c.name)
    if (!deployment) {
      missing.push(c.name)
    }
    return deployment
  })

  if (missing.length > 0) {
    throw new Error(`${missing.join(', ')} not deployed. Run required deploy tags first.`)
  }

  return deployments as NonNullable<(typeof deployments)[number]>[]
}

/**
 * Get proxy infrastructure (implementation) for a proxied contract
 */
export function getProxyInfrastructure(env: Environment, contract: RegistryEntry) {
  const implDep = env.getOrNull(`${contract.name}_Implementation`)
  return { implementation: implDep }
}

/**
 * Read per-proxy ProxyAdmin address from ERC1967 admin slot
 * OZ v5 TransparentUpgradeableProxy creates its own ProxyAdmin stored in this slot
 */
export async function getProxyAdminAddress(client: PublicClient, proxyAddress: string): Promise<string> {
  const adminSlotData = await client.getStorageAt({
    address: proxyAddress as `0x${string}`,
    slot: ERC1967_ADMIN_SLOT as `0x${string}`,
  })
  if (!adminSlotData) {
    throw new Error(`Failed to read admin slot from proxy ${proxyAddress}`)
  }
  return `0x${adminSlotData.slice(-40)}`
}

/**
 * Show standard deployment status message
 */
export function showDeploymentStatus(
  env: Environment,
  contract: RegistryEntry,
  result: { newlyDeployed?: boolean; address: string },
) {
  if (result.newlyDeployed) {
    env.showMessage(`✓ ${contract.name} deployed at ${result.address}`)
  } else {
    env.showMessage(`✓ ${contract.name} deployed at ${result.address}`)
  }
}

/**
 * Show standard proxy deployment status messages
 */
export function showProxyDeploymentStatus(
  env: Environment,
  contract: RegistryEntry,
  result: { newlyDeployed?: boolean; address: string },
  implAddress?: string,
  governor?: string,
) {
  if (result.newlyDeployed) {
    env.showMessage(`✓ ${contract.name} proxy deployed at ${result.address}`)
    if (implAddress) {
      env.showMessage(`✓ ${contract.name} implementation at ${implAddress}`)
    }
    if (governor) {
      env.showMessage(`✓ Governor role assigned to: ${governor}`)
    }
  } else {
    env.showMessage(`✓ ${contract.name} deployed at ${result.address}`)
  }
}

/**
 * Update issuance address book with proxy deployment information
 */
export async function updateProxyAddressBook(
  env: Environment,
  graphUtils: typeof graph,
  contract: RegistryEntry,
  proxyAddress: string,
  implAddress?: string,
  proxyAdminAddress?: string,
  implementationDeployment?: DeploymentMetadata,
) {
  await graphUtils.updateIssuanceAddressBook(env, {
    name: contract.name,
    address: proxyAddress,
    proxy: 'transparent',
    proxyAdmin: proxyAdminAddress,
    implementation: implAddress,
    implementationDeployment,
  })
}

/**
 * Check if proxy has pending upgrade and display warning if needed
 *
 * Compares on-chain implementation with newly deployed implementation.
 * If they differ, displays upgrade warning for governance action.
 *
 * @param env - Deployment environment
 * @param client - Viem public client
 * @param contract - Contract registry entry
 * @param proxyAddress - Address of the proxy contract
 * @param proxyType - 'transparent' for OZ TransparentProxy, 'graph' for Graph legacy proxy
 * @param proxyAdminAddress - Address of proxy admin (required for 'graph' type)
 */
export async function checkPendingUpgrade(
  env: Environment,
  client: PublicClient,
  contract: RegistryEntry,
  proxyAddress: string,
  proxyType: 'transparent' | 'graph' = 'transparent',
  proxyAdminAddress?: string,
) {
  // Get implementation deployment if it exists
  const implDeployment = env.getOrNull(`${contract.name}_Implementation`)
  if (!implDeployment) {
    return
  }

  // Get on-chain implementation
  const onChainImpl = await getOnChainImplementation(client, proxyAddress, proxyType, proxyAdminAddress)

  // Check if upgrade is pending
  if (onChainImpl.toLowerCase() !== implDeployment.address.toLowerCase()) {
    env.showMessage(``)
    env.showMessage(`⚠️  UPGRADE REQUIRED`)
    env.showMessage(`   Proxy:               ${proxyAddress}`)
    env.showMessage(`   Current (on-chain):  ${onChainImpl}`)
    env.showMessage(`   New implementation:  ${implDeployment.address}`)
    env.showMessage(``)
    env.showMessage(`   Governance must upgrade the proxy.`)
    env.showMessage(``)
  } else {
    env.showMessage(`✓ Current implementation: ${onChainImpl}`)
  }
}

/**
 * Configuration for deploying a proxy contract
 */
export interface ProxyDeployConfig {
  /** Contract registry entry (provides addressBook and artifact config) */
  contract: RegistryEntry
  /** Constructor arguments for implementation (not used when sharedImplementation provided) */
  constructorArgs?: unknown[]
  /** Initialize function arguments (defaults to [governor] if not provided) */
  initializeArgs?: unknown[]
  /**
   * Shared implementation contract (optional)
   * When provided, deploys proxy pointing to this existing implementation
   * instead of deploying a new implementation from contract.artifact
   */
  sharedImplementation?: RegistryEntry
}

/**
 * Deploy or upgrade a proxy contract using OZ v5 TransparentUpgradeableProxy
 *
 * Uses OpenZeppelin v5's per-proxy ProxyAdmin pattern:
 * - Each proxy creates its own ProxyAdmin in the constructor
 * - Governor owns all per-proxy ProxyAdmins
 * - No shared ProxyAdmin required
 *
 * Deployment scenarios:
 * - Fresh deployment: Deploy implementation + OZ v5 proxy (creates per-proxy ProxyAdmin)
 * - Existing proxy: Deploy new implementation, store as pending for governance upgrade
 *
 * For shared implementations (sharedImplementation provided):
 * - Fresh deployment: Deploy OZ v5 proxy pointing to shared implementation
 * - Existing proxy: Reports status only (shared impl managed separately)
 *
 * @param env - Deployment environment
 * @param config - Deployment configuration
 * @returns Deployment result with address and status
 */
export async function deployProxyContract(
  env: Environment,
  config: ProxyDeployConfig,
): Promise<{ address: string; newlyDeployed: boolean; upgraded: boolean }> {
  const { contract, constructorArgs = [], initializeArgs, sharedImplementation } = config

  // Validate contract has required metadata
  if (!sharedImplementation && !contract.artifact) {
    throw new Error(`No artifact configured for ${contract.name} in registry (and no sharedImplementation provided)`)
  }

  // Derive values from environment
  const deployer = requireDeployer(env)
  const governor = await getGovernor(env)
  const actualInitializeArgs = initializeArgs ?? [governor]

  // Check if proxy already exists (synced from address book)
  const existingProxy = env.getOrNull(`${contract.name}_Proxy`)

  if (existingProxy) {
    if (sharedImplementation) {
      // Shared implementation - just report status
      env.showMessage(`✓ ${contract.name} proxy already deployed at ${existingProxy.address}`)
      env.showMessage(`   Uses shared implementation: ${sharedImplementation.name}`)

      // Check current implementation status
      const client = graph.getPublicClient(env)
      await checkPendingUpgrade(env, client, contract, existingProxy.address, 'transparent')

      return {
        address: existingProxy.address,
        newlyDeployed: false,
        upgraded: false,
      }
    }

    // Own implementation - use deployImplementation for upgrade pattern
    env.showMessage(`   Existing proxy found at ${existingProxy.address}, using upgrade pattern`)

    const implResult = await deployImplementation(
      env,
      getImplementationConfig(contract.addressBook, contract.name, {
        constructorArgs,
      }),
    )

    if (implResult.deployed) {
      env.showMessage(`✓ New implementation deployed at ${implResult.address}`)
      env.showMessage(`   Upgrade TX required via governance`)
    } else {
      env.showMessage(`✓ Implementation unchanged at ${implResult.address}`)
    }

    // Check pending upgrade status
    const client = graph.getPublicClient(env)
    await checkPendingUpgrade(env, client, contract, existingProxy.address, 'transparent')

    return {
      address: existingProxy.address,
      newlyDeployed: false,
      upgraded: implResult.deployed,
    }
  }

  // Fresh deployment - deploy implementation first, then OZ v5 proxy
  if (sharedImplementation) {
    return deployProxyWithSharedImpl(env, contract, sharedImplementation, governor, actualInitializeArgs, deployer)
  }

  return deployProxyWithOwnImpl(env, contract, governor, constructorArgs, actualInitializeArgs, deployer)
}

/**
 * Deploy proxy with its own implementation (OZ v5 pattern)
 */
async function deployProxyWithOwnImpl(
  env: Environment,
  contract: RegistryEntry,
  governor: string,
  constructorArgs: unknown[],
  initializeArgs: unknown[],
  deployer: string,
): Promise<{ address: string; newlyDeployed: boolean; upgraded: boolean }> {
  const deployFn = deploy(env)

  // Deploy implementation
  const implArtifact = loadArtifactFromSource(contract.artifact!)
  const implResult = await deployFn(
    `${contract.name}_Implementation`,
    {
      account: deployer,
      artifact: implArtifact,
      args: constructorArgs,
    },
    { alwaysOverride: true },
  )

  env.showMessage(`   Implementation deployed at ${implResult.address}`)

  // Encode initialize call
  const initCalldata = encodeFunctionData({
    abi: INITIALIZE_GOVERNOR_ABI,
    functionName: 'initialize',
    args: initializeArgs as [`0x${string}`],
  })

  // Deploy OZ v5 TransparentUpgradeableProxy
  // Constructor: (address _logic, address initialOwner, bytes memory _data)
  // The proxy creates its own ProxyAdmin owned by initialOwner (governor)
  // Use issuance-compiled proxy artifact (0.8.33) for consistent verification
  const proxyArtifact = loadTransparentProxyArtifact()
  const proxyResult = await deployFn(
    `${contract.name}_Proxy`,
    {
      account: deployer,
      artifact: proxyArtifact,
      args: [implResult.address, governor, initCalldata],
    },
    { skipIfAlreadyDeployed: true },
  )

  // Read per-proxy ProxyAdmin address from ERC1967 slot
  const client = graph.getPublicClient(env)
  const proxyAdminAddress = await getProxyAdminAddress(client, proxyResult.address)

  // Save main contract deployment (proxy address with implementation ABI)
  await env.save(contract.name, {
    ...proxyResult,
    abi: implArtifact.abi,
  })

  // Build implementation deployment metadata for address book (only if we have required fields)
  let implementationDeployment: DeploymentMetadata | undefined
  if (implResult.transaction?.hash && implResult.argsData && implResult.deployedBytecode) {
    implementationDeployment = {
      txHash: implResult.transaction.hash,
      argsData: implResult.argsData,
      bytecodeHash: computeBytecodeHash(implResult.deployedBytecode),
      ...(implResult.receipt?.blockNumber && { blockNumber: Number(implResult.receipt.blockNumber) }),
    }
  }

  // Update address book with per-proxy ProxyAdmin and deployment metadata
  await updateProxyAddressBook(
    env,
    graph,
    contract,
    proxyResult.address,
    implResult.address,
    proxyAdminAddress,
    implementationDeployment,
  )

  if (proxyResult.newlyDeployed) {
    env.showMessage(`✓ ${contract.name} proxy deployed at ${proxyResult.address}`)
    env.showMessage(`   Implementation: ${implResult.address}`)
    env.showMessage(`   ProxyAdmin (per-proxy): ${proxyAdminAddress}`)
  } else {
    env.showMessage(`✓ ${contract.name} already deployed at ${proxyResult.address}`)
  }

  return {
    address: proxyResult.address,
    newlyDeployed: !!proxyResult.newlyDeployed,
    upgraded: false,
  }
}

/**
 * Deploy proxy pointing to a shared implementation (OZ v5 pattern)
 */
async function deployProxyWithSharedImpl(
  env: Environment,
  contract: RegistryEntry,
  sharedImplementation: RegistryEntry,
  governor: string,
  initializeArgs: unknown[],
  deployer: string,
): Promise<{ address: string; newlyDeployed: boolean; upgraded: boolean }> {
  const deployFn = deploy(env)

  // Get shared implementation deployment
  const implDep = env.getOrNull(sharedImplementation.name)
  if (!implDep) {
    throw new Error(`Shared implementation ${sharedImplementation.name} not deployed. Deploy it first.`)
  }

  env.showMessage(`   Deploying ${contract.name} proxy with shared implementation: ${sharedImplementation.name}`)

  // Encode initialize call
  const initCalldata = encodeFunctionData({
    abi: INITIALIZE_GOVERNOR_ABI,
    functionName: 'initialize',
    args: initializeArgs as [`0x${string}`],
  })

  // Deploy OZ v5 TransparentUpgradeableProxy
  // Constructor: (address _logic, address initialOwner, bytes memory _data)
  // Use issuance-compiled proxy artifact (0.8.33) for consistent verification
  const proxyArtifact = loadTransparentProxyArtifact()
  const proxyResult = await deployFn(
    `${contract.name}_Proxy`,
    {
      account: deployer,
      artifact: proxyArtifact,
      args: [implDep.address, governor, initCalldata],
    },
    { skipIfAlreadyDeployed: true },
  )

  // Read per-proxy ProxyAdmin address from ERC1967 slot
  const client = graph.getPublicClient(env)
  const proxyAdminAddress = await getProxyAdminAddress(client, proxyResult.address)

  // Save main contract deployment (proxy address with implementation ABI)
  await env.save(contract.name, {
    ...proxyResult,
    abi: implDep.abi,
  })

  // Update address book with per-proxy ProxyAdmin
  await updateProxyAddressBook(env, graph, contract, proxyResult.address, implDep.address, proxyAdminAddress)

  if (proxyResult.newlyDeployed) {
    env.showMessage(`✓ ${contract.name} proxy deployed at ${proxyResult.address}`)
    env.showMessage(`   Implementation: ${implDep.address}`)
    env.showMessage(`   ProxyAdmin (per-proxy): ${proxyAdminAddress}`)
  } else {
    env.showMessage(`✓ ${contract.name} already deployed at ${proxyResult.address}`)
  }

  return {
    address: proxyResult.address,
    newlyDeployed: !!proxyResult.newlyDeployed,
    upgraded: false,
  }
}
