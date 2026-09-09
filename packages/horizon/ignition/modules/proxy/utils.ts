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
  const { id: customId, ...rest } = options ?? {}
  let proxyWithABI
  if (contract.artifact === undefined) {
    proxyWithABI = m.contractAt(customId ?? contract.name, proxy, rest)
  } else {
    proxyWithABI = m.contractAt(customId ?? `${contract.name}_ProxyWithABI`, contract.artifact, proxy, rest)
  }
  return proxyWithABI
}
