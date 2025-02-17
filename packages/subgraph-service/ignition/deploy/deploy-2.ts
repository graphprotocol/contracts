import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import CurationModule from '../modules/Curation'
import DisputeManagerModule from '../modules/DisputeManager'
import SubgraphServiceModule from '../modules/SubgraphService'

export default buildModule('SubgraphService_Deploy_2', (m) => {
  const { L2Curation, L2CurationImplementation } = m.useModule(CurationModule)
  const { DisputeManager, DisputeManagerImplementation } = m.useModule(DisputeManagerModule)
  const { SubgraphService, SubgraphServiceImplementation } = m.useModule(SubgraphServiceModule)

  return {
    Graph_Proxy_L2Curation: L2Curation,
    Implementation_L2Curation: L2CurationImplementation,
    Transparent_Proxy_DisputeManager: DisputeManager,
    Implementation_DisputeManager: DisputeManagerImplementation,
    Transparent_Proxy_SubgraphService: SubgraphService,
    Implementation_SubgraphService: SubgraphServiceImplementation,
  }
})
