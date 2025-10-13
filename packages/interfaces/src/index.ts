import { ContractRunner, Interface } from 'ethers'

import { factories } from '../types'

export * from './interfaceIds'
export * from './types/horizon'
export * from './types/subgraph-service'

/**
 * Interface representing a static contract factory with methods to create interfaces and connect to contracts
 * @template ContractType - The type of the contract instance
 * @template InterfaceType - The type of the contract interface
 */
interface ContractFactoryStatic<ContractType = unknown, InterfaceType = Interface> {
  readonly abi: unknown[]
  createInterface(): InterfaceType
  connect(address: string, runner?: ContractRunner | null): ContractType
}

/**
 * Gets the contract interface for a given contract name
 * @param {string} contractName - The name of the contract to get the interface for
 * @returns {Interface} The contract interface
 * @throws {Error} If no interface is found for the given contract name
 */
export function getInterface(contractName: string): Interface {
  const alternatives = getContractNameAlternatives(contractName)
  for (const alternative of alternatives) {
    const factory = collectFactoriesMap(factories)[alternative]
    if (factory) {
      return factory.createInterface()
    }
  }
  throw new Error(`No interface found for contract ${contractName}`)
}

/**
 * Loads and merges interfaces from multiple contract names.
 *
 * @param names Array of contract names
 * @returns Merged ethers.js Interface
 */
export function getMergedInterface(names: string[]): Interface {
  const abis = names.map((name) => {
    const iface = getInterface(name)
    return (iface as Interface).fragments
  })

  const mergedFragments = abis.flat()

  return new Interface(mergedFragments)
}

/**
 * Gets the ABI for a given contract name
 * @param {string} contractName - The name of the contract to get the ABI for
 * @returns {unknown[]} The contract ABI
 * @throws {Error} If no ABI is found for the given contract name
 */
export function getAbi(contractName: string): unknown[] {
  const alternatives = getContractNameAlternatives(contractName)
  for (const alternative of alternatives) {
    const factory = collectFactoriesMap(factories)[alternative]
    if (factory) {
      return factory.abi
    }
  }
  throw new Error(`No abi found for contract ${contractName}`)
}

/**
 * Collects all contract factories from the given object into a map by recursively traversing the object structure.
 * Handles factory name overrides and normalizes contract names by removing '__factory' suffix.
 *
 * @param {unknown} obj - The object containing contract factories to be collected
 * @returns {Record<string, ContractFactoryStatic>} A map of contract names to their factory instances
 * @private
 */
function collectFactoriesMap(obj: unknown): Record<string, ContractFactoryStatic> {
  const factoriesMap: Record<string, ContractFactoryStatic> = {}

  // For factory name 'x', use contract name 'y'
  // This is necessary because DisputeManager name collision, its the name of the contract in both the contracts and subgraph-service packages
  const factoryNameOverrides: Record<string, string> = {
    'contracts.contracts.disputes.IDisputeManager__factory': 'ILegacyDisputeManager',
  }

  function recurse(value: unknown, path: string[] = []) {
    if (typeof value !== 'object' || value === null) {
      return
    }

    const entries = Object.entries(value)

    for (const [key, val] of entries) {
      const currentPath = [...path, key]
      const currentPathString = currentPath.join('.')

      if (key.endsWith('__factory')) {
        const descriptor = Object.getOwnPropertyDescriptor(value, key)
        const factory = descriptor?.get ? descriptor.get.call(value) : val

        const contractName = factoryNameOverrides[currentPathString]
          ? factoryNameOverrides[currentPathString]
          : key.replace(/__factory$/, '')

        if (factoriesMap[contractName]) {
          console.log(
            `⚠️  Duplicate factory for contract "${contractName}" found at path "${currentPathString}". Keeping the first occurrence. If both are needed add overrides.`,
          )
          continue
        }

        // Add main entry
        factoriesMap[contractName] = factory as ContractFactoryStatic
      } else if (typeof val === 'object' && val !== null) {
        recurse(val, currentPath)
      }
    }
  }

  recurse(obj)

  return factoriesMap
}

/**
 * Gets alternative names for a contract to handle interface naming conventions
 * For any given value passed to it, returns `ContractName` and `IContractName`
 * Note that this function will apply toolshed overrides if available as they are more complete interfaces
 * @param {string} contractName - The original contract name
 * @returns {string[]} Array of possible contract names including interface variants
 * @private
 */
function getContractNameAlternatives(contractName: string): string[] {
  const nameOverrides: Record<string, string> = {
    Controller: 'ControllerToolshed',
    DisputeManager: 'DisputeManagerToolshed',
    EpochManager: 'EpochManagerToolshed',
    L2GNS: 'L2GNSToolshed',
    GraphTallyCollector: 'GraphTallyCollectorToolshed',
    GraphTokenLockWallet: 'GraphTokenLockWalletToolshed',
    HorizonStaking: 'HorizonStakingToolshed',
    L2Curation: 'L2CurationToolshed',
    PaymentsEscrow: 'PaymentsEscrowToolshed',
    RewardsManager: 'RewardsManagerToolshed',
    SubgraphService: 'SubgraphServiceToolshed',
    ServiceRegistry: 'ServiceRegistryToolshed',
    LegacyServiceRegistry: 'ServiceRegistryToolshed',
  }

  // override with toolshed alternative if available
  if (nameOverrides[contractName]) {
    contractName = nameOverrides[contractName]
  }

  const alternatives: string[] = [contractName]
  alternatives.push(contractName.startsWith('I') ? contractName.replace('I', '') : `I${contractName}`)

  return alternatives
}
