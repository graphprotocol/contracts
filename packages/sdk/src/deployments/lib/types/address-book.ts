import type { DeployResult } from './deploy'

// TODO: doc this

// JSON format:
// {
//   "<CHAIN_ID>": {
//     "<CONTRACT_NAME>": {}
//     ...
//    }
// }
export type AddressBookJson<
  ChainId extends number = number,
  ContractName extends string = string,
> = Record<ChainId, Record<ContractName, AddressBookEntry>>

export type ConstructorArg = string | Array<string>

export type AddressBookEntry = {
  address: string
  constructorArgs?: Array<ConstructorArg>
  initArgs?: Array<string>
  proxy?: boolean
  implementation?: AddressBookEntry
} & Partial<Omit<DeployResult, 'contract'>>
