/* eslint-disable no-prototype-builtins */
/* eslint-disable @typescript-eslint/no-unsafe-return */
/* eslint-disable @typescript-eslint/no-explicit-any */
require('json5/lib/register')

import fs from 'fs'
import path from 'path'
import { AddressBook } from '../address-book'

export function loadConfig(configPath: string, prefix: string, networkName: string): any {
  const configFileCandidates = [
    path.resolve(process.cwd(), configPath, `${prefix}.${networkName}.json5`),
    path.resolve(process.cwd(), configPath, `${prefix}.default.json5`),
  ]

  const configFile = configFileCandidates.find(file => fs.existsSync(file))
  if (!configFile) {
    throw new Error(
      `Config file not found. Tried:\n${configFileCandidates.map(f => `- ${f}`).join('\n')}`,
    )
  }

  return { config: removeNFromBigInts(require(configFile)), file: configFile }
}

export function patchConfig(jsonData: any, patches: Record<string, any>) {
  function recursivePatch(obj: any) {
    if (typeof obj === 'object' && obj !== null) {
      for (const key in obj) {
        if (key in patches) {
          obj[key] = patches[key]
        } else {
          recursivePatch(obj[key])
        }
      }
    }
  }

  recursivePatch(jsonData)
  return jsonData
}

export function mergeConfigs(obj1: any, obj2: any) {
  const merged = { ...obj1 }

  for (const key in obj2) {
    if (obj2.hasOwnProperty(key)) {
      if (typeof obj2[key] === 'object' && obj2[key] !== null && obj1[key]) {
        merged[key] = mergeConfigs(obj1[key], obj2[key])
      } else {
        merged[key] = obj2[key]
      }
    }
  }

  return merged
}

export function saveToAddressBook<ChainId extends number, ContractName extends string>(
  contracts: any,
  chainId: number | undefined,
  addressBook: AddressBook<ChainId, ContractName>,
): AddressBook<ChainId, ContractName> {
  if (!chainId) {
    throw new Error('Chain ID is required')
  }

  // Extract contract names and addresses
  for (const [ignitionContractName, contract] of Object.entries(contracts)) {
    // Proxy contracts
    if (ignitionContractName.includes('_Proxy_')) {
      const contractName = ignitionContractName.replace(/(Transparent_Proxy_|Graph_Proxy_)/, '') as ContractName
      const proxy = ignitionContractName.includes('Transparent_Proxy_') ? 'transparent' : 'graph'
      const entry = addressBook.getEntry(contractName)
      addressBook.setEntry(contractName, {
        ...entry,
        address: (contract as any).target,
        proxy,
      })
    }

    // Proxy admin contracts
    if (ignitionContractName.includes('_ProxyAdmin_')) {
      const contractName = ignitionContractName.replace(/(Transparent_ProxyAdmin_|Graph_ProxyAdmin_)/, '') as ContractName
      const proxy = ignitionContractName.includes('Transparent_ProxyAdmin_') ? 'transparent' : 'graph'
      const entry = addressBook.getEntry(contractName)
      addressBook.setEntry(contractName, {
        ...entry,
        proxy,
        proxyAdmin: (contract as any).target,
      })
    }

    // Implementation contracts
    if (ignitionContractName.startsWith('Implementation_')) {
      const contractName = ignitionContractName.replace('Implementation_', '') as ContractName
      const entry = addressBook.getEntry(contractName)
      addressBook.setEntry(contractName, {
        ...entry,
        implementation: (contract as any).target,
      })
    }

    // Non proxied contracts
    if (addressBook.isContractName(ignitionContractName)) {
      const entry = addressBook.getEntry(ignitionContractName)
      addressBook.setEntry(ignitionContractName, {
        ...entry,
        address: (contract as any).target,
      })
    }
  }

  return addressBook
}

// Ignition requires "n" suffix for bigints, but not here
function removeNFromBigInts(obj: any): any {
  if (typeof obj === 'string') {
    return obj.replace(/(\d+)n/g, '$1')
  } else if (Array.isArray(obj)) {
    return obj.map(removeNFromBigInts)
  } else if (typeof obj === 'object' && obj !== null) {
    for (const key in obj) {
      obj[key] = removeNFromBigInts(obj[key])
    }
  }
  return obj
}
