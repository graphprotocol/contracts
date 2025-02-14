import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import ProxiesModule from '../Proxies'

export default buildModule('SubgraphService_Migrate_1', (m) => {
  const {
    Transparent_Proxy_SubgraphService,
    Transparent_ProxyAdmin_SubgraphService,
    Transparent_Proxy_DisputeManager,
    Transparent_ProxyAdmin_DisputeManager,
  } = m.useModule(ProxiesModule)

  return {
    Transparent_Proxy_SubgraphService,
    Transparent_ProxyAdmin_SubgraphService,
    Transparent_Proxy_DisputeManager,
    Transparent_ProxyAdmin_DisputeManager,
  }
})
