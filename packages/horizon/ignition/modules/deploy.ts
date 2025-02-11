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
    GraphTallyCollector,
  } = m.useModule(GraphHorizonCoreModule)

  const governor = m.getAccount(1)

  // BUG?: acceptOwnership should be called after everything in GraphHorizonCoreModule and GraphPeripheryModule is resolved
  // but it seems that it's not waiting for interal calls. Waiting on HorizonStaking seems to fix the issue for some reason
  // Removing HorizonStaking from the after list will trigger the bug

  // Accept ownership of Graph Governed based contracts
  m.call(Controller, 'acceptOwnership', [], { from: governor, after: [GraphPeripheryModule, GraphHorizonCoreModule, HorizonStaking] })
  m.call(GraphProxyAdmin, 'acceptOwnership', [], { from: governor, after: [GraphPeripheryModule, GraphHorizonCoreModule, HorizonStaking] })

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
    GraphTallyCollector,
  }
})
