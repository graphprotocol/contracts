import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphHorizonCoreModule from './core/core'
import GraphPeripheryModule from './periphery/periphery'

export default buildModule('GraphHorizon_Deploy', (m) => {
  const {
    Controller,
    EpochManager,
    EpochManagerImplementation,
    GraphProxyAdmin,
    L2GraphTokenGateway,
    L2GraphTokenGatewayImplementation,
    L2GraphToken,
    L2GraphTokenImplementation,
    RewardsManager,
    RewardsManagerImplementation,
    L2Curation,
    L2CurationImplementation,
  } = m.useModule(GraphPeripheryModule)
  const {
    HorizonStaking,
    HorizonStakingImplementation,
    GraphPayments,
    GraphPaymentsImplementation,
    PaymentsEscrow,
    PaymentsEscrowImplementation,
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
    Graph_Proxy_EpochManager: EpochManager,
    Implementation_EpochManager: EpochManagerImplementation,
    Graph_Proxy_L2Curation: L2Curation,
    Implementation_L2Curation: L2CurationImplementation,
    Graph_Proxy_RewardsManager: RewardsManager,
    Implementation_RewardsManager: RewardsManagerImplementation,
    Graph_Proxy_L2GraphTokenGateway: L2GraphTokenGateway,
    Implementation_L2GraphTokenGateway: L2GraphTokenGatewayImplementation,
    Graph_Proxy_L2GraphToken: L2GraphToken,
    Implementation_L2GraphToken: L2GraphTokenImplementation,
    GraphProxyAdmin,
    Graph_Proxy_HorizonStaking: HorizonStaking,
    Implementation_HorizonStaking: HorizonStakingImplementation,
    Transparent_Proxy_GraphPayments: GraphPayments,
    Implementation_GraphPayments: GraphPaymentsImplementation,
    Transparent_Proxy_PaymentsEscrow: PaymentsEscrow,
    Implementation_PaymentsEscrow: PaymentsEscrowImplementation,
    GraphTallyCollector,
  }
})
