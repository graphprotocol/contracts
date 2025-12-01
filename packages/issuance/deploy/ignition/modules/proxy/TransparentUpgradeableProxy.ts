import {
  CallableContractFuture,
  ContractFuture,
  ContractOptions,
  IgnitionModuleBuilder,
} from '@nomicfoundation/ignition-core'
import DummyArtifact from '@openzeppelin/contracts/build/contracts/ERC1967Utils.json'
import ProxyAdminArtifact from '@openzeppelin/contracts/build/contracts/ProxyAdmin.json'
import TransparentUpgradeableProxyArtifact from '@openzeppelin/contracts/build/contracts/TransparentUpgradeableProxy.json'

import { deployImplementation, type ImplementationMetadata } from './implementation'
import { loadProxyWithABI } from './utils'

// Deploy a TransparentUpgradeableProxy
// The TransparentUpgradeableProxy contract creates the ProxyAdmin within its constructor.
export function deployTransparentUpgradeableProxy(
  m: IgnitionModuleBuilder,
  metadata: ImplementationMetadata,
  implementation?: ContractFuture<string>,
  options?: ContractOptions,
) {
  const deployer = m.getAccount(0)

  // The proxy requires a valid contract as initial implementation so we use a dummy
  if (implementation === undefined) {
    implementation = m.contract('Dummy', DummyArtifact, [], { ...options, id: `OZProxyDummy_${metadata.name}` })
  }

  const TransparentUpgradeableProxy = m.contract(
    'TransparentUpgradeableProxy',
    TransparentUpgradeableProxyArtifact,
    [implementation, deployer, '0x'],
    {
      ...options,
      id: `TransparentUpgradeableProxy_${metadata.name}`,
    },
  )

  const proxyAdminAddress = m.readEventArgument(TransparentUpgradeableProxy, 'AdminChanged', 'newAdmin', {
    ...options,
    id: `TransparentUpgradeableProxy_${metadata.name}_AdminChanged`,
  })

  const ProxyAdmin = m.contractAt('ProxyAdmin', ProxyAdminArtifact, proxyAdminAddress, {
    ...options,
    id: `ProxyAdmin_${metadata.name}`,
  })

  const proxy = loadProxyWithABI(m, TransparentUpgradeableProxy, metadata, options)

  return { proxy, proxyAdmin: ProxyAdmin }
}

// Upgrade a TransparentUpgradeableProxy to a new implementation
export function upgradeTransparentUpgradeableProxy(
  m: IgnitionModuleBuilder,
  proxyAdmin: CallableContractFuture<string>,
  proxy: ContractFuture<string>,
  implementation: ContractFuture<string>,
  metadata: ImplementationMetadata,
  options?: ContractOptions,
) {
  // Upgrade proxy to implementation contract
  m.call(proxyAdmin, 'upgradeAndCall', [proxy, implementation, '0x'], options)

  // Initialize the proxy if initArgs are provided
  if (metadata.initArgs !== undefined && metadata.initArgs.length > 0) {
    const proxyWithABI = loadProxyWithABI(m, proxy, metadata, options)
    m.call(proxyWithABI, 'initialize', metadata.initArgs, options)
  }

  return loadProxyWithABI(m, proxy, metadata, options)
}

// Deploy implementation and proxy together
export function deployWithTransparentUpgradeableProxy(
  m: IgnitionModuleBuilder,
  metadata: ImplementationMetadata,
  options?: ContractOptions,
) {
  options = options || {}

  // Deploy implementation
  const implementation = deployImplementation(m, metadata, options)

  // Deploy proxy
  const { proxy, proxyAdmin } = deployTransparentUpgradeableProxy(m, metadata, implementation, options)

  // Initialize the proxy if initArgs are provided
  if (metadata.initArgs !== undefined && metadata.initArgs.length > 0) {
    m.call(proxy, 'initialize', metadata.initArgs, options)
  }

  return { proxy, proxyAdmin, implementation }
}

