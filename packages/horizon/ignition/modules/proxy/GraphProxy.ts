/* eslint-disable @typescript-eslint/no-explicit-any */
import {
  CallableContractFuture,
  ContractFuture,
  ContractOptions,
  IgnitionModuleBuilder,
  ModuleParameterRuntimeValue,
} from '@nomicfoundation/ignition-core'

import { deployImplementation, type ImplementationMetadata } from './implementation'
import { loadProxyWithABI } from './utils'

import GraphProxyArtifact from '@graphprotocol/contracts/build/contracts/contracts/upgrades/GraphProxy.sol/GraphProxy.json'

export function deployGraphProxy(
  m: IgnitionModuleBuilder,
  proxyAdmin: ContractFuture<string>,
  implementation?: ContractFuture<string>,
  metadata?: ImplementationMetadata,
  options?: ContractOptions,
) {
  if (implementation === undefined || metadata === undefined) {
    const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'
    return m.contract('GraphProxy', GraphProxyArtifact, [ZERO_ADDRESS, proxyAdmin], options)
  } else {
    const GraphProxy = m.contract('GraphProxy', GraphProxyArtifact, [implementation, proxyAdmin], options)
    return loadProxyWithABI(m, GraphProxy, metadata, options)
  }
}

export function upgradeGraphProxy(
  m: IgnitionModuleBuilder,
  proxyAdmin: CallableContractFuture<string>,
  proxy: string | ModuleParameterRuntimeValue<string>,
  implementation: ContractFuture<string>,
  metadata: ImplementationMetadata,
  options?: ContractOptions,
) {
  const GraphProxy = m.contractAt('GraphProxy', GraphProxyArtifact, proxy)

  const upgradeCall = m.call(proxyAdmin, 'upgrade', [GraphProxy, implementation], options)
  const acceptCall = m.call(proxyAdmin, 'acceptProxy', [implementation, GraphProxy], { ...options, after: [upgradeCall] })

  return loadProxyWithABI(m, GraphProxy, metadata, { ...options, after: [acceptCall] })
}

// Same as upgradeGraphProxy, but without loading the proxy contracts
export function upgradeGraphProxyNoLoad(
  m: IgnitionModuleBuilder,
  proxyAdmin: CallableContractFuture<string>,
  proxy: CallableContractFuture<string>,
  implementation: ContractFuture<string>,
  metadata: ImplementationMetadata,
  options?: ContractOptions,
) {
  const upgradeCall = m.call(proxyAdmin, 'upgrade', [proxy, implementation], options)
  const acceptCall = m.call(proxyAdmin, 'acceptProxy', [implementation, proxy], { ...options, after: [upgradeCall] })

  return loadProxyWithABI(m, proxy, metadata, { ...options, after: [acceptCall] })
}

export function deployWithGraphProxy(
  m: IgnitionModuleBuilder,
  proxyAdmin: CallableContractFuture<string>,
  metadata: ImplementationMetadata,
  options?: ContractOptions,
) {
  options = options || {}

  // Deploy implementation
  const implementation = deployImplementation(m, metadata, options)

  // Deploy proxy and initialize
  const proxy = deployGraphProxy(m, proxyAdmin, implementation, metadata, options)
  if (metadata.initArgs === undefined) {
    m.call(proxyAdmin, 'acceptProxy', [implementation, proxy], options)
  } else {
    m.call(proxyAdmin, 'acceptProxyAndCall', [implementation, proxy, m.encodeFunctionCall(implementation, 'initialize', metadata.initArgs)], options)
  }

  return proxy
}
