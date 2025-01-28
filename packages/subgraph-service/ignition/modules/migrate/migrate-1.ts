import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import ProxiesModule from '../Proxies'

export default buildModule('SubgraphService_Migrate_1', (m) => {
  const {
    SubgraphServiceProxy,
    SubgraphServiceProxyAdmin,
    DisputeManagerProxy,
    DisputeManagerProxyAdmin,
  } = m.useModule(ProxiesModule)

  return {
    SubgraphServiceProxy,
    SubgraphServiceProxyAdmin,
    DisputeManagerProxy,
    DisputeManagerProxyAdmin,
  }
})
