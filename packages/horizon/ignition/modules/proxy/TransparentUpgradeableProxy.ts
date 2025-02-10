import { CallableContractFuture, ContractFuture, ContractOptions, IgnitionModuleBuilder } from '@nomicfoundation/ignition-core'
import { ImplementationMetadata } from './implementation'
import { loadProxyWithABI } from './utils'

// Importing artifacts from build directory so we have all build artifacts for contract verification
import DummyArtifact from '../../../build/contracts/contracts/mocks/Dummy.sol/Dummy.json'
import ProxyAdminArtifact from '../../../build/contracts/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol/ProxyAdmin.json'
import TransparentUpgradeableProxyArtifact from '../../../build/contracts/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol/TransparentUpgradeableProxy.json'

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

  const Proxy = m.contract('TransparentUpgradeableProxy', TransparentUpgradeableProxyArtifact, [
    implementation,
    deployer,
    '0x',
  ],
  { ...options, id: `TransparentUpgradeableProxy_${metadata.name}` })

  const proxyAdminAddress = m.readEventArgument(
    Proxy,
    'AdminChanged',
    'newAdmin',
    { ...options, id: `TransparentUpgradeableProxy_${metadata.name}_AdminChanged` },
  )

  const ProxyAdmin = m.contractAt('ProxyAdmin', ProxyAdminArtifact, proxyAdminAddress, { ...options, id: `ProxyAdmin_${metadata.name}` })

  if (implementation !== undefined) {
    return { ProxyAdmin, Proxy: loadProxyWithABI(m, Proxy, metadata, options) }
  } else {
    return { ProxyAdmin, Proxy }
  }
}

export function upgradeTransparentUpgradeableProxy(
  m: IgnitionModuleBuilder,
  proxyAdmin: CallableContractFuture<string>,
  proxy: CallableContractFuture<string>,
  implementation: CallableContractFuture<string>,
  metadata: ImplementationMetadata,
  options?: ContractOptions,
) {
  const upgradeCall = m.call(proxyAdmin, 'upgradeAndCall',
    [proxy, implementation, m.encodeFunctionCall(implementation, 'initialize', metadata.initArgs)],
    options,
  )
  return loadProxyWithABI(m, proxy, metadata, { ...options, after: [upgradeCall] })
}
