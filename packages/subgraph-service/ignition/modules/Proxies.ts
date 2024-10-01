import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import { deployWithOZProxy } from '@graphprotocol/horizon/ignition/modules/proxy/TransparentUpgradeableProxy'

export default buildModule('SubgraphServiceProxies', (m) => {
  // Deploy proxies contracts using OZ TransparentUpgradeableProxy
  const { Proxy: DisputeManagerProxy, ProxyAdmin: DisputeManagerProxyAdmin } = deployWithOZProxy(m, 'DisputeManager')
  const { Proxy: SubgraphServiceProxy, ProxyAdmin: SubgraphServiceProxyAdmin } = deployWithOZProxy(m, 'SubgraphService')

  return { DisputeManagerProxy, DisputeManagerProxyAdmin, SubgraphServiceProxy, SubgraphServiceProxyAdmin }
})
