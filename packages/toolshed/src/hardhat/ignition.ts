import fs from 'fs'
import { parse } from 'json5'
import path from 'path'

import type { AddressBook } from '../deployments/address-book'

type IgnitionConfigValue = string | number
type IgnitionConfig = {
  [key: string]: Record<string, IgnitionConfigValue>
}

export function loadConfig(configPath: string, prefix: string, configName: string): {
  config: IgnitionConfig
  file: string
} {
  prefix = process.env.IGNITION_DEPLOYMENT_TYPE ?? prefix

  const configFileCandidates = [
    path.resolve(process.cwd(), configPath, `${prefix}.${configName}.json5`),
    path.resolve(process.cwd(), configPath, `${prefix}.default.json5`),
  ]

  const configFile = configFileCandidates.find(file => fs.existsSync(file))
  if (!configFile) {
    throw new Error(
      `Config file not found. Tried:\n${configFileCandidates.map(f => `- ${f}`).join('\n')}`,
    )
  }

  const config = parse<IgnitionConfig>(fs.readFileSync(configFile, 'utf8'))

  return {
    config: removeNFromBigInts(config),
    file: configFile,
  }
}

export function patchConfig(jsonData: IgnitionConfig, patches: IgnitionConfig): IgnitionConfig {
  const result: IgnitionConfig = { ...jsonData }
  for (const [key, patchValue] of Object.entries(patches)) {
    const existingValue = result[key]
    if (existingValue) {
      result[key] = { ...existingValue, ...patchValue }
    } else {
      result[key] = patchValue
    }
  }
  return result
}

type IgnitionModuleResult = {
  [key: string]: {
    target: string
  }
}

export function saveToAddressBook<ChainId extends number, ContractName extends string>(
  ignitionModuleResult: unknown,
  addressBook: AddressBook<ChainId, ContractName>,
): AddressBook<ChainId, ContractName> {
  const contracts = ignitionModuleResult as IgnitionModuleResult
  for (const [ignitionContractName, contract] of Object.entries(contracts)) {
    // Proxy contracts
    if (ignitionContractName.includes('_Proxy_')) {
      const contractName = ignitionContractName.replace(/(Transparent_Proxy_|Graph_Proxy_)/, '') as ContractName
      const proxy = ignitionContractName.includes('Transparent_Proxy_') ? 'transparent' : 'graph'
      const entry = addressBook.entryExists(contractName) ? addressBook.getEntry(contractName) : {}
      addressBook.setEntry(contractName, {
        ...entry,
        address: contract.target,
        proxy,
      })
    }

    // Proxy admin contracts
    if (ignitionContractName.includes('_ProxyAdmin_')) {
      const contractName = ignitionContractName.replace(/(Transparent_ProxyAdmin_|Graph_ProxyAdmin_)/, '') as ContractName
      const proxy = ignitionContractName.includes('Transparent_ProxyAdmin_') ? 'transparent' : 'graph'
      const entry = addressBook.entryExists(contractName) ? addressBook.getEntry(contractName) : {}
      addressBook.setEntry(contractName, {
        ...entry,
        proxy,
        proxyAdmin: contract.target,
      })
    }

    // Implementation contracts
    if (ignitionContractName.startsWith('Implementation_')) {
      const contractName = ignitionContractName.replace('Implementation_', '') as ContractName
      const entry = addressBook.entryExists(contractName) ? addressBook.getEntry(contractName) : {}
      addressBook.setEntry(contractName, {
        ...entry,
        implementation: contract.target,
      })
    }

    // Non proxied contracts
    if (addressBook.isContractName(ignitionContractName)) {
      const entry = addressBook.entryExists(ignitionContractName) ? addressBook.getEntry(ignitionContractName) : {}
      addressBook.setEntry(ignitionContractName, {
        ...entry,
        address: contract.target,
      })
    }
  }

  return addressBook
}

// Ignition requires "n" suffix for bigints, but not in js runtime
function removeNFromBigInts(config: IgnitionConfig): IgnitionConfig {
  const result: IgnitionConfig = {}
  for (const [key, value] of Object.entries(config)) {
    if (typeof value === 'object') {
      result[key] = Object.fromEntries(
        Object.entries(value).map(([k, v]) => [
          k,
          typeof v === 'string' && /^\d+n$/.test(v) ? v.slice(0, -1) : v,
        ]),
      )
    }
  }
  return result
}
