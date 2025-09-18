import {
  ContractAtFuture,
  ContractFuture,
  ContractOptions,
  IgnitionModuleBuilder,
} from '@nomicfoundation/ignition-core'

import type { ImplementationMetadata } from './implementation'

export function loadProxyWithABI(
  m: IgnitionModuleBuilder,
  proxy: ContractFuture<string> | ContractAtFuture,
  contract: ImplementationMetadata,
  options?: ContractOptions,
) {
  let proxyWithABI
  if (contract.artifact === undefined) {
    proxyWithABI = m.contractAt(contract.name, proxy, options)
  } else {
    proxyWithABI = m.contractAt(`${contract.name}_ProxyWithABI`, contract.artifact, proxy, options)
  }
  return proxyWithABI
}
