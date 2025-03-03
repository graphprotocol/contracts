import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import CurationModule from '../Curation'
import DisputeManagerModule from '../DisputeManager'
import SubgraphServiceModule from '../SubgraphService'

export default buildModule('SubgraphService_Deploy_2', (m) => {
  const { DisputeManager, DisputeManagerImplementation } = m.useModule(DisputeManagerModule)
  const { SubgraphService, SubgraphServiceImplementation } = m.useModule(SubgraphServiceModule)
  const { L2Curation, L2CurationImplementation } = m.useModule(CurationModule)
  return {
    Transparent_Proxy_DisputeManager: DisputeManager,
    Implementation_DisputeManager: DisputeManagerImplementation,
    Transparent_Proxy_SubgraphService: SubgraphService,
    Implementation_SubgraphService: SubgraphServiceImplementation,
    Graph_Proxy_L2Curation: L2Curation,
    Implementation_L2Curation: L2CurationImplementation,
  }
})
