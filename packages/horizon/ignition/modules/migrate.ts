import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import { MigrateHorizonCoreModule } from './core/core'
import { MigratePeripheryModule } from './periphery/periphery'

export default buildModule('GraphHorizon_Migrate', (m) => {
  const {
    L2Curation,
    RewardsManager,
    Controller,
    GraphProxyAdmin,
    EpochManager,
    GraphToken,
    GraphTokenGateway,
  } = m.useModule(MigratePeripheryModule)

  const {
    HorizonStaking,
    GraphPayments,
    PaymentsEscrow,
    TAPCollector,
  } = m.useModule(MigrateHorizonCoreModule)

  return {
    L2Curation,
    RewardsManager,
    HorizonStaking,
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
