import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import DisputeManagerModule from '../DisputeManager'
import SubgraphServiceModule from '../SubgraphService'

export default buildModule('SubgraphService_Migrate_2', (m) => {
  const { DisputeManager, DisputeManagerImplementation } = m.useModule(DisputeManagerModule)
  const { SubgraphService, SubgraphServiceImplementation } = m.useModule(SubgraphServiceModule)

  return {
    Transparent_Proxy_DisputeManager: DisputeManager,
    Transparent_ProxyAdmin_DisputeManager: DisputeManagerImplementation,
    Transparent_Proxy_SubgraphService: SubgraphService,
    Transparent_ProxyAdmin_SubgraphService: SubgraphServiceImplementation,
  }
})
