import fs from 'fs'
import YAML from 'yaml'
import { Scalar, YAMLMap } from 'yaml/types'
import { AddressBook } from './address-book'

import type {
  ABRefReplace,
  ContractConfig,
  ContractConfigCall,
  ContractConfigParam,
} from './types/config'
import type { ContractParam } from './types/contract'

// TODO: tidy this up
const ABRefMatcher = /\${{([A-Z]\w.+)}}/

function parseConfigValue(value: string, addressBook: AddressBook, deployerAddress: string) {
  return isAddressBookRef(value)
    ? parseAddressBookRef(addressBook, value, [{ ref: 'Env.deployer', replace: deployerAddress }])
    : value
}

function isAddressBookRef(value: string): boolean {
  return ABRefMatcher.test(value)
}

function parseAddressBookRef(
  addressBook: AddressBook,
  value: string,
  abInject: ABRefReplace[],
): string {
  const valueMatch = ABRefMatcher.exec(value)
  if (valueMatch === null) {
    throw new Error('Could not parse address book reference')
  }
  const ref = valueMatch[1]
  const [contractName, contractAttr] = ref.split('.')

  // This is a convention to inject variables into the config, for example the deployer address
  const inject = abInject.find((ab) => ab.ref === ref)
  if (inject) {
    return inject.replace
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const entry = addressBook.getEntry(contractName) as { [key: string]: any }
  return entry[contractAttr]
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function readConfig(path: string, retainMetadata = false): any {
  const file = fs.readFileSync(path, 'utf8')
  return retainMetadata ? YAML.parseDocument(file) : YAML.parse(file)
}

export function writeConfig(path: string, data: string): void {
  fs.writeFileSync(path, data)
}

export function loadCallParams(
  values: Array<ContractParam>,
  addressBook: AddressBook,
  deployerAddress: string,
): Array<ContractParam> {
  return values.map((value) => parseConfigValue(value as string, addressBook, deployerAddress))
}

export function getContractConfig(
  config: any,
  addressBook: AddressBook,
  name: string,
  deployerAddress: string,
): ContractConfig {
  const contractConfig = config.contracts[name] || {}
  const contractParams: Array<ContractConfigParam> = []
  const contractCalls: Array<ContractConfigCall> = []
  let proxy = false

  const optsList = Object.entries(contractConfig) as Array<Array<string>>
  for (const [name, value] of optsList) {
    // Process constructor params
    if (name.startsWith('init')) {
      const initList = Object.entries(contractConfig.init) as Array<Array<string>>
      for (const [initName, initValue] of initList) {
        contractParams.push({
          name: initName,
          value: parseConfigValue(initValue, addressBook, deployerAddress),
        })
      }
      continue
    }

    // Process contract calls
    if (name.startsWith('calls')) {
      for (const entry of contractConfig.calls) {
        const fn = entry['fn']
        const params = Object.values(entry).slice(1) as Array<ContractParam> // skip fn
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

// YAML helper functions
const getNode = (doc: YAML.Document.Parsed, path: string[]): YAMLMap | undefined => {
  try {
    let node: YAMLMap | undefined
    for (const p of path) {
      node = node === undefined ? doc.get(p) : node.get(p)
    }
    return node
  } catch (error) {
    throw new Error(`Could not find node: ${path}.`)
  }
}

function getItem(node: YAMLMap, key: string): Scalar {
  if (!node.has(key)) {
    throw new Error(`Could not find item: ${key}.`)
  }
  return node.get(key, true) as Scalar
}

function getItemFromPath(doc: YAML.Document.Parsed, path: string) {
  const splitPath = path.split('/')
  const itemKey = splitPath.pop()
  if (itemKey === undefined) {
    throw new Error('Badly formed path.')
  }

  const node = getNode(doc, splitPath)
  if (node === undefined) {
    return undefined
  }

  const item = getItem(node, itemKey)
  return item
}

export const getItemValue = (doc: YAML.Document.Parsed, path: string): any => {
  const item = getItemFromPath(doc, path)
  return item?.value
}

export const updateItemValue = (doc: YAML.Document.Parsed, path: string, value: any): boolean => {
  const item = getItemFromPath(doc, path)
  if (item === undefined) {
    throw new Error(`Could not find item: ${path}.`)
  }
  const updated = item.value !== value
  item.value = value
  return updated
}
