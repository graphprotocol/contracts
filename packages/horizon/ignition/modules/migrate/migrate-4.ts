import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import { MigrateCurationGovernorModule } from '../periphery/Curation'
import { MigrateHorizonStakingGovernorModule } from '../core/HorizonStaking'
import { MigrateRewardsManagerGovernorModule } from '../periphery/RewardsManager'

export default buildModule('GraphHorizon_Migrate_4', (m) => {
  const {
    L2Curation,
    L2CurationImplementation,
  } = m.useModule(MigrateCurationGovernorModule)

  const {
    RewardsManager,
    RewardsManagerImplementation,
  } = m.useModule(MigrateRewardsManagerGovernorModule)

  const {
    HorizonStaking,
    HorizonStakingImplementation,
  } = m.useModule(MigrateHorizonStakingGovernorModule)

  return {
    Graph_Proxy_L2Curation: L2Curation,
    Implementation_L2Curation: L2CurationImplementation,
    Graph_Proxy_RewardsManager: RewardsManager,
    Implementation_RewardsManager: RewardsManagerImplementation,
    Graph_Proxy_HorizonStaking: HorizonStaking,
    Implementation_HorizonStaking: HorizonStakingImplementation,
  }
})
