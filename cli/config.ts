import fs from 'fs'
import YAML from 'yaml'

import { AddressBook } from './address-book'

const ABRefMatcher = /\${{([A-Z]\w.+)}}/

type ContractParams = Array<{ name: string; value: string }>
type ContractCalls = Array<{ fn: string; params: Array<any> }>

interface ContractConfig {
  params: ContractParams
  calls: ContractCalls
  proxy: boolean
}

function parseConfigValue(value: string, addressBook: AddressBook) {
  if (isAddressBookRef(value)) {
    return parseAddressBookRef(addressBook, value)
  }
  return value
}

function isAddressBookRef(value: string): boolean {
  return ABRefMatcher.test(value)
}

function parseAddressBookRef(addressBook: AddressBook, value: string): string {
  const ref: string = ABRefMatcher.exec(value as string)[1]
  const [contractName, contractAttr] = ref.split('.')
  const entry = addressBook.getEntry(contractName) as { [key: string]: any }
  return entry[contractAttr]
}

export function readConfig(path: string) {
  const file = fs.readFileSync(path, 'utf8')
  return YAML.parse(file)
}

export function getContractConfig(
  config: any,
  addressBook: AddressBook,
  name: string,
): ContractConfig {
  const contractConfig = config.contracts[name] || {}
  const contractParams: ContractParams = []
  const contractCalls: ContractCalls = []
  let proxy = false

  const optsList = Object.entries(contractConfig) as Array<Array<string>>
  for (const [name, value] of optsList) {
    // Process constructor params
    if (name.startsWith('init')) {
      const initList = Object.entries(contractConfig.init) as Array<Array<string>>
      for (const [initName, initValue] of initList) {
        contractParams.push({ name: initName, value: parseConfigValue(initValue, addressBook) } as {
          name: string
          value: string
        })
      }
      continue
    }

    // Process contract calls
    if (name.startsWith('calls')) {
      for (const entry of contractConfig.calls) {
        const fn = entry['fn']
        const params = Object.entries(entry)
          .slice(1) // skip fn
          .map(([, value]) => parseConfigValue(value as string, addressBook))
        contractCalls.push({ fn, params })
      }
      continue
    }

    // Process proxy
    if (name.startsWith('proxy')) {
      proxy = Boolean(value)
      continue
    }
  }

  return {
    params: contractParams,
    calls: contractCalls,
    proxy,
  }
}
