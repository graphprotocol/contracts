import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import { MigrateCurationModule } from './periphery/Curation'
import { MigrateRewardsManagerModule } from './periphery/RewardsManager'
export default buildModule('GraphHorizon_Periphery', (m) => {
  const { L2Curation } = m.useModule(MigrateCurationModule)
  const { RewardsManager } = m.useModule(MigrateRewardsManagerModule)

  return {
    L2Curation,
    RewardsManager,
  }
})
