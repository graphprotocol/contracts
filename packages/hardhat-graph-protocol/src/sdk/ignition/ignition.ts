/* eslint-disable no-prototype-builtins */
/* eslint-disable @typescript-eslint/no-unsafe-return */
/* eslint-disable @typescript-eslint/no-explicit-any */
require('json5/lib/register')

import fs from 'fs'
import path from 'path'

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

  return removeNFromBigInts(require(configFile))
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

export function saveAddressBook(
  contracts: any,
  chainId: number | undefined,
  addressBook = 'addresses.json',
): Record<string, Record<string, string>> {
  if (!chainId) {
    throw new Error('Chain ID is required')
  }

  // Use different address book for local networks - this one can be gitignored
  if ([1377, 31337].includes(chainId)) {
    addressBook = 'addresses-local.json'
  }

  const output = fs.existsSync(addressBook)
    ? JSON.parse(fs.readFileSync(addressBook, 'utf8'))
    : {}

  output[chainId] = output[chainId] || {}

  // Extract contract names and addresses
  Object.entries(contracts).forEach(([contractName, contract]: [string, any]) => {
    output[chainId][contractName] = contract.target
  })

  // Write to output file
  const outputDir = path.dirname(addressBook)
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true })
  }

  fs.writeFileSync(addressBook, JSON.stringify(output, null, 2))

  return output as Record<string, Record<string, string>>
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
