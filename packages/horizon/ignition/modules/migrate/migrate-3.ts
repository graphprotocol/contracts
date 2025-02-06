import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import { MigrateHorizonCoreModule } from '../core/core'
import { MigratePeripheryModule } from '../periphery/periphery'

export default buildModule('GraphHorizon_Migrate_3', (m) => {
  const {
    L2Curation,
    L2CurationImplementation,
    RewardsManager,
    RewardsManagerImplementation,
    Controller,
    GraphProxyAdmin,
    EpochManager,
    GraphToken,
    GraphTokenGateway,
  } = m.useModule(MigratePeripheryModule)

  const {
    HorizonStaking,
    HorizonStakingImplementation,
    GraphPayments,
    PaymentsEscrow,
    TAPCollector,
  } = m.useModule(MigrateHorizonCoreModule)

  return {
    L2Curation,
    L2CurationImplementation,
    RewardsManager,
    RewardsManagerImplementation,
    HorizonStaking,
    HorizonStakingImplementation,
    GraphPayments,
    PaymentsEscrow,
    TAPCollector,
    Controller,
    GraphProxyAdmin,
    EpochManager,
    GraphToken,
    GraphTokenGateway,
  }
})
