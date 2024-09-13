import { ArgumentType, Artifact, ContractOptions, IgnitionModuleBuilder } from '@nomicfoundation/ignition-core'

import GraphProxyAdminModule from '../periphery/GraphProxyAdmin'
import GraphProxyArtifact from '@graphprotocol/contracts/build/contracts/contracts/upgrades/GraphProxy.sol/GraphProxy.json'

export function deployWithGraphProxy(m: IgnitionModuleBuilder, contract: { name: string, artifact?: Artifact, args?: ArgumentType[] }, options?: ContractOptions) {
  const { GraphProxyAdmin } = m.useModule(GraphProxyAdminModule)

  options = options || {}

  // Deploy implementation
  let implementation
  if (contract.artifact === undefined) {
    implementation = m.contract(contract.name, [], options)
  } else {
    implementation = m.contract(contract.name, contract.artifact, [], options)
  }

  // Deploy proxy and initialize
  const proxy = m.contract('GraphProxy', GraphProxyArtifact, [implementation, GraphProxyAdmin], options)
  if (contract.args === undefined) {
    m.call(GraphProxyAdmin, 'acceptProxy', [implementation, proxy], options)
  } else {
    m.call(GraphProxyAdmin, 'acceptProxyAndCall', [implementation, proxy, m.encodeFunctionCall(implementation, 'initialize', contract.args)], options)
  }

  // Load proxy with implementation ABI
  let instance
  if (contract.artifact === undefined) {
    instance = m.contractAt(contract.name, proxy, options)
  } else {
    instance = m.contractAt(`${contract.name}_Instance`, contract.artifact, proxy, options)
  }

  return { proxy, implementation, instance }
}
