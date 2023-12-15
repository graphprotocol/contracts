import type { ContractParam } from './contract'

export type ContractConfigParam = { name: string; value: string }
export type ContractConfigCall = { fn: string; params: Array<ContractParam> }
export interface ContractConfig {
  params: Array<ContractConfigParam>
  calls: Array<ContractConfigCall>
  proxy: boolean
}

export interface ABRefReplace {
  ref: string
  replace: string
}
