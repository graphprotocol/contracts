import fs from 'fs'
import YAML from 'yaml'
import { Scalar, YAMLMap } from 'yaml/types'

import { AddressBook } from './address-book'
import { CLIEnvironment } from './env'

const ABRefMatcher = /\${{([A-Z]\w.+)}}/

type ContractParam = { name: string; value: string }
type ContractCall = { fn: string; params: Array<ContractCallParam> }
type ContractCallParam = string | number
interface ContractConfig {
  params: Array<ContractParam>
  calls: Array<ContractCall>
  proxy: boolean
}

function parseConfigValue(value: string, addressBook: AddressBook, cli: CLIEnvironment) {
  if (isAddressBookRef(value)) {
    return parseAddressBookRef(addressBook, value, cli)
  }
  return value
}

function isAddressBookRef(value: string): boolean {
  return ABRefMatcher.test(value)
}

function parseAddressBookRef(addressBook: AddressBook, value: string, cli: CLIEnvironment): string {
  const ref: string = ABRefMatcher.exec(value as string)[1]
  const [contractName, contractAttr] = ref.split('.')
  // This is a convention to use the inject CLI-env variables into the config
  if (contractName === 'Env') {
    if (contractAttr == 'deployer') {
      return cli.walletAddress
    }
    throw new Error('Attribute not found in the CLI env')
  }
  // eslint-disable-next-line  @typescript-eslint/no-explicit-any
  const entry = addressBook.getEntry(contractName) as { [key: string]: any }
  return entry[contractAttr]
}

// eslint-disable-next-line  @typescript-eslint/no-explicit-any
export function readConfig(path: string, retainMetadata = false): any {
  const file = fs.readFileSync(path, 'utf8')
  return retainMetadata ? YAML.parseDocument(file) : YAML.parse(file)
}

export function writeConfig(path: string, data: string): void {
  fs.writeFileSync(path, data)
}

export function loadCallParams(
  values: Array<ContractCallParam>,
  addressBook: AddressBook,
  cli: CLIEnvironment,
): Array<ContractCallParam> {
  return values.map((value) => parseConfigValue(value as string, addressBook, cli))
}

export function getContractConfig(
  config: any,
  addressBook: AddressBook,
  name: string,
  cli: CLIEnvironment,
): ContractConfig {
  const contractConfig = config.contracts[name] || {}
  const contractParams: Array<ContractParam> = []
  const contractCalls: Array<ContractCall> = []
  let proxy = false

  const optsList = Object.entries(contractConfig) as Array<Array<string>>
  for (const [name, value] of optsList) {
    // Process constructor params
    if (name.startsWith('init')) {
      const initList = Object.entries(contractConfig.init) as Array<Array<string>>
      for (const [initName, initValue] of initList) {
        contractParams.push({
          name: initName,
          value: parseConfigValue(initValue, addressBook, cli),
        } as {
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
        const params = Object.values(entry).slice(1) as Array<ContractCallParam> // skip fn
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
const getNode = (doc: YAML.Document.Parsed, path: string[]): YAMLMap => {
  try {
    let node: YAMLMap
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

  const node = getNode(doc, splitPath)
  const item = getItem(node, itemKey)
  return item
}

export const getItemValue = (doc: YAML.Document.Parsed, path: string): any => {
  const item = getItemFromPath(doc, path)
  return item.value
}

export const updateItemValue = (doc: YAML.Document.Parsed, path: string, value: any): boolean => {
  const item = getItemFromPath(doc, path)
  const updated = item.value !== value
  item.value = value
  return updated
}
