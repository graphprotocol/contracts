import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphHorizonCoreModule from './core'
import GraphPeripheryModule from './periphery'

export default buildModule('GraphHorizon', (m) => {
  const {
    BridgeEscrow,
    Controller,
    EpochManager,
    GraphProxyAdmin,
    GraphTokenGateway,
    RewardsManager,
    Curation,
  } = m.useModule(GraphPeripheryModule)
  const { HorizonStaking, GraphPayments, PaymentsEscrow, TAPCollector } = m.useModule(GraphHorizonCoreModule)

  return {
    BridgeEscrow,
    Controller,
    Curation,
    EpochManager,
    GraphProxyAdmin,
    GraphTokenGateway,
    RewardsManager,
    HorizonStaking,
    GraphPayments,
    PaymentsEscrow,
    TAPCollector,
  }
})
