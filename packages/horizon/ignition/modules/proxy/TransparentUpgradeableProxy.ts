import { IgnitionModuleBuilder } from '@nomicfoundation/ignition-core'

import DummyArtifact from '../../../build/contracts/contracts/mocks/Dummy.sol/Dummy.json'
import ProxyAdminArtifact from '../../../build/contracts/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol/ProxyAdmin.json'
import TransparentUpgradeableProxyArtifact from '../../../build/contracts/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol/TransparentUpgradeableProxy.json'

// Deploy a TransparentUpgradeableProxy
// Note that this module uses a dummy contract as the implementation as the proxy requires a valid contract
// address to be deployed
export function deployWithOZProxy(m: IgnitionModuleBuilder, contractName: string) {
  const deployer = m.getAccount(0)

  const dummy = m.contract('Dummy', DummyArtifact, [], { id: `OZProxyDummy_${contractName}` })
  const Proxy = m.contract('TransparentUpgradeableProxy', TransparentUpgradeableProxyArtifact, [
    dummy,
    deployer,
    '0x',
  ],
  { id: `TransparentUpgradeableProxy_${contractName}` })

  const proxyAdminAddress = m.readEventArgument(
    Proxy,
    'AdminChanged',
    'newAdmin',
    {
      id: `TransparentUpgradeableProxy_${contractName}_AdminChanged`,
    },
  )

  const ProxyAdmin = m.contractAt('ProxyAdmin', ProxyAdminArtifact, proxyAdminAddress, { id: `ProxyAdmin_${contractName}` })

  return { ProxyAdmin, Proxy }
}
