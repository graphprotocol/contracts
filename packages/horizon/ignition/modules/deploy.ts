import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphHorizonCoreModule from './core/core'
import GraphPeripheryModule from './periphery/periphery'

export default buildModule('GraphHorizon', (m) => {
  const {
    BridgeEscrow,
    Controller,
    EpochManager,
    GraphProxyAdmin,
    GraphTokenGateway,
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
    BridgeEscrow,
    Controller,
    L2Curation,
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
