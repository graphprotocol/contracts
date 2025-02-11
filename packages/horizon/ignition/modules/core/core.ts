import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphPaymentsModule, { MigrateGraphPaymentsModule } from './GraphPayments'
import HorizonStakingModule, { MigrateHorizonStakingDeployerModule } from './HorizonStaking'
import PaymentsEscrowModule, { MigratePaymentsEscrowModule } from './PaymentsEscrow'
import GraphTallyCollectorModule, { MigrateGraphTallyCollectorModule } from './GraphTallyCollector'

export default buildModule('GraphHorizon_Core', (m) => {
  const { HorizonStaking } = m.useModule(HorizonStakingModule)
  const { GraphPayments } = m.useModule(GraphPaymentsModule)
  const { PaymentsEscrow } = m.useModule(PaymentsEscrowModule)
  const { GraphTallyCollector } = m.useModule(GraphTallyCollectorModule)

  return { HorizonStaking, GraphPayments, PaymentsEscrow, GraphTallyCollector }
})

export const MigrateHorizonCoreModule = buildModule('GraphHorizon_Core', (m) => {
  const { HorizonStakingProxy: HorizonStaking, HorizonStakingImplementation } = m.useModule(MigrateHorizonStakingDeployerModule)
  const { GraphPayments } = m.useModule(MigrateGraphPaymentsModule)
  const { PaymentsEscrow } = m.useModule(MigratePaymentsEscrowModule)
  const { GraphTallyCollector } = m.useModule(MigrateGraphTallyCollectorModule)

  return { HorizonStaking, HorizonStakingImplementation, GraphPayments, PaymentsEscrow, GraphTallyCollector }
})
