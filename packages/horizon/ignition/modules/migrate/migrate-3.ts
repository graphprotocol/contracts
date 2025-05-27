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
    L2GraphToken,
    L2GraphTokenGateway,
    L2GNS,
    L2GNSImplementation,
    SubgraphNFT,
  } = m.useModule(MigratePeripheryModule)

  const {
    HorizonStaking,
    HorizonStakingImplementation,
    GraphPayments,
    GraphPaymentsImplementation,
    PaymentsEscrow,
    PaymentsEscrowImplementation,
    GraphTallyCollector,
  } = m.useModule(MigrateHorizonCoreModule)

  return {
    Graph_Proxy_L2Curation: L2Curation,
    Implementation_L2Curation: L2CurationImplementation,
    Graph_Proxy_L2GNS: L2GNS,
    Implementation_L2GNS: L2GNSImplementation,
    SubgraphNFT,
    Graph_Proxy_RewardsManager: RewardsManager,
    Implementation_RewardsManager: RewardsManagerImplementation,
    Graph_Proxy_HorizonStaking: HorizonStaking,
    Implementation_HorizonStaking: HorizonStakingImplementation,
    Transparent_Proxy_GraphPayments: GraphPayments,
    Implementation_GraphPayments: GraphPaymentsImplementation,
    Transparent_Proxy_PaymentsEscrow: PaymentsEscrow,
    Implementation_PaymentsEscrow: PaymentsEscrowImplementation,
    GraphTallyCollector,
    Controller: Controller,
    GraphProxyAdmin,
    Graph_Proxy_EpochManager: EpochManager,
    Graph_Proxy_L2GraphToken: L2GraphToken,
    Graph_Proxy_L2GraphTokenGateway: L2GraphTokenGateway,
  }
})
