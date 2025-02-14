import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import DisputeManagerModule from '../DisputeManager'
import SubgraphServiceModule from '../SubgraphService'

export default buildModule('SubgraphService_Migrate_2', (m) => {
  const { Transparent_Proxy_DisputeManager, Implementation_DisputeManager } = m.useModule(DisputeManagerModule)
  const { Transparent_Proxy_SubgraphService, Implementation_SubgraphService } = m.useModule(SubgraphServiceModule)

  return {
    Transparent_Proxy_DisputeManager,
    Implementation_DisputeManager,
    Transparent_Proxy_SubgraphService,
    Implementation_SubgraphService,
  }
})
