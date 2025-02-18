import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import ProxiesModule from '../Proxies'

export default buildModule('SubgraphService_Deploy_1', (m) => {
  const {
    SubgraphServiceProxy,
    SubgraphServiceProxyAdmin,
    DisputeManagerProxy,
    DisputeManagerProxyAdmin,
  } = m.useModule(ProxiesModule)

  return {
    Transparent_Proxy_SubgraphService: SubgraphServiceProxy,
    Transparent_ProxyAdmin_SubgraphService: SubgraphServiceProxyAdmin,
    Transparent_Proxy_DisputeManager: DisputeManagerProxy,
    Transparent_ProxyAdmin_DisputeManager: DisputeManagerProxyAdmin,
  }
})
