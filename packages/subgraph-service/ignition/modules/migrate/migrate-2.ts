import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import DisputeManagerModule from '../DisputeManager'
import SubgraphServiceModule from '../SubgraphService'

export default buildModule('SubgraphService_Migrate_2', (m) => {
  const { DisputeManager } = m.useModule(DisputeManagerModule)
  const { SubgraphService } = m.useModule(SubgraphServiceModule)

  return { DisputeManager, SubgraphService }
})
