import { AddressBook } from '../address-book'
import { isSomeEnum } from '../../../utils/type-guard'

import type { Contract, Signer } from 'ethers'
import type { ContractParam } from './contract'
import type { Libraries } from './artifacts'

export enum DeployType {
  Deploy = 'deploy',
  DeployAndSave = 'deploy-save',
  DeployWithProxy = 'deploy-with-proxy',
  DeployWithProxyAndSave = 'deploy-with-proxy-save',
  DeployImplementationAndSave = 'deploy-implementation-save',
}

export type DeployData = {
  name: string
  args?: Array<ContractParam>
  opts?: Record<string, any>
}

export type DeployResult = {
  contract: Contract
  creationCodeHash: string
  runtimeCodeHash: string
  txHash: string
  libraries?: Libraries
}

// Utility type to add parameters to a function interface
// https://stackoverflow.com/a/69668215
type AddParameters<TFunction extends (...args: any) => any, TParameters extends [...args: any]> = (
  ...args: [...Parameters<TFunction>, ...TParameters]
) => ReturnType<TFunction>

export type DeployFunction = (sender: Signer, contract: DeployData) => Promise<DeployResult>

export type DeployAddressBookFunction = (
  sender: Signer,
  contract: DeployData,
  addressBook: AddressBook,
) => Promise<DeployResult>
export type DeployAddressBookWithProxyFunction = AddParameters<
  DeployAddressBookFunction,
  [proxy: DeployData]
>

// ** Type guards **
export function isDeployType(value: unknown): value is DeployType {
  return isSomeEnum(DeployType)(value)
}
