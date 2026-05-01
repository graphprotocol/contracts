import type { Environment } from '@rocketh/core/types'

import type { RegistryEntry } from './contract-registry.js'
import { loadArtifactFromSource } from './deploy-implementation.js'
import { requireDeployer } from './issuance-deploy-utils.js'
import { deploy, graph } from '../rocketh/deploy.js'

/**
 * Configuration for deploying a standalone (non-proxy) contract
 */
export interface StandaloneDeployConfig {
  /** Contract registry entry (provides addressBook and artifact config) */
  contract: RegistryEntry
  /** Constructor arguments */
  constructorArgs?: unknown[]
}

/**
 * Deploy a standalone (non-proxy) contract and update the address book
 *
 * This utility handles the common pattern for deploying contracts that
 * are not behind a proxy (e.g., helper contracts).
 *
 * - Loads artifact from registry metadata
 * - Deploys via rocketh (idempotent - skips if bytecode unchanged)
 * - Updates the appropriate address book (horizon or issuance)
 *
 * @example
 * ```typescript
 * await deployStandaloneContract(env, {
 *   contract: Contracts.horizon.GraphTallyCollector,
 *   constructorArgs: [controllerAddress],
 * })
 * ```
 */
export async function deployStandaloneContract(
  env: Environment,
  config: StandaloneDeployConfig,
): Promise<{ address: string; newlyDeployed: boolean }> {
  const { contract, constructorArgs = [] } = config

  if (!contract.artifact) {
    throw new Error(`No artifact configured for ${contract.name} in registry`)
  }

  const deployer = requireDeployer(env)
  const artifact = loadArtifactFromSource(contract.artifact)
  const deployFn = deploy(env)

  const result = await deployFn(contract.name, {
    account: deployer,
    artifact,
    args: constructorArgs,
  })

  if (result.newlyDeployed) {
    env.showMessage(`\n✓ ${contract.name} deployed at ${result.address}`)
  } else {
    env.showMessage(`\n✓ ${contract.name} unchanged at ${result.address}`)
  }

  // Update address book based on which book the contract belongs to
  if (contract.addressBook === 'horizon') {
    await graph.updateHorizonAddressBook(env, {
      name: contract.name,
      address: result.address,
    })
  } else if (contract.addressBook === 'issuance') {
    await graph.updateIssuanceAddressBook(env, {
      name: contract.name,
      address: result.address,
    })
  }

  return {
    address: result.address,
    newlyDeployed: !!result.newlyDeployed,
  }
}
