import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import { MigrateCurationGovernorModule } from '../periphery/Curation'
import { MigrateHorizonStakingGovernorModule } from '../core/HorizonStaking'
import { MigrateRewardsManagerGovernorModule } from '../periphery/RewardsManager'

export default buildModule('GraphHorizon_Migrate_4', (m) => {
  const {
    L2Curation,
  } = m.useModule(MigrateCurationGovernorModule)

  const {
    RewardsManager,
  } = m.useModule(MigrateRewardsManagerGovernorModule)

  const {
    HorizonStaking,
  } = m.useModule(MigrateHorizonStakingGovernorModule)

  return {
    L2Curation,
    RewardsManager,
    HorizonStaking,
  }
})
