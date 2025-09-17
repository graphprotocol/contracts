import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import { MigrateHorizonStakingGovernorModule } from '../core/HorizonStaking'
import { MigrateCurationGovernorModule } from '../periphery/Curation'
import { MigrateRewardsManagerGovernorModule } from '../periphery/RewardsManager'

export default buildModule('GraphHorizon_Migrate_4', (m) => {
  m.useModule(MigrateCurationGovernorModule)
  m.useModule(MigrateRewardsManagerGovernorModule)
  m.useModule(MigrateHorizonStakingGovernorModule)

  return {}
})
