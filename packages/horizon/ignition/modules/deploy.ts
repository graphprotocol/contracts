import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphHorizonCoreModule from './core/core'
import GraphPeripheryModule from './periphery/periphery'

export default buildModule('GraphHorizon_Deploy', (m) => {
  const {
    Controller,
    EpochManager,
    GraphProxyAdmin,
    GraphTokenGateway,
    GraphToken,
    RewardsManager,
    L2Curation,
  } = m.useModule(GraphPeripheryModule)
  const {
    HorizonStaking,
    GraphPayments,
    PaymentsEscrow,
    TAPCollector,
  } = m.useModule(GraphHorizonCoreModule)

  return {
    Controller,
    L2Curation,
    EpochManager,
    GraphProxyAdmin,
    GraphTokenGateway,
    GraphToken,
    RewardsManager,
    HorizonStaking,
    GraphPayments,
    PaymentsEscrow,
    TAPCollector,
  }
})
