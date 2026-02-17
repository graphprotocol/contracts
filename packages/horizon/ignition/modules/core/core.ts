import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphPaymentsModule, { MigrateGraphPaymentsModule } from './GraphPayments'
import GraphTallyCollectorModule, { MigrateGraphTallyCollectorModule } from './GraphTallyCollector'
import HorizonStakingModule, { MigrateHorizonStakingDeployerModule } from './HorizonStaking'
import RecurringCollectorModule, { MigrateRecurringCollectorModule } from './RecurringCollector'
import PaymentsEscrowModule, { MigratePaymentsEscrowModule } from './PaymentsEscrow'

export default buildModule('GraphHorizon_Core', (m) => {
  const { HorizonStaking, HorizonStakingImplementation } = m.useModule(HorizonStakingModule)
  const { GraphPaymentsProxyAdmin, GraphPayments, GraphPaymentsImplementation } = m.useModule(GraphPaymentsModule)
  const { PaymentsEscrowProxyAdmin, PaymentsEscrow, PaymentsEscrowImplementation } = m.useModule(PaymentsEscrowModule)
  const { GraphTallyCollector } = m.useModule(GraphTallyCollectorModule)
  const { RecurringCollector } = m.useModule(RecurringCollectorModule)

  return {
    HorizonStaking,
    HorizonStakingImplementation,
    GraphPaymentsProxyAdmin,
    GraphPayments,
    GraphPaymentsImplementation,
    PaymentsEscrowProxyAdmin,
    PaymentsEscrow,
    PaymentsEscrowImplementation,
    GraphTallyCollector,
    RecurringCollector,
  }
})

export const MigrateHorizonCoreModule = buildModule('GraphHorizon_Core', (m) => {
  const { HorizonStakingProxy: HorizonStaking, HorizonStakingImplementation } = m.useModule(
    MigrateHorizonStakingDeployerModule,
  )
  const { GraphPayments, GraphPaymentsImplementation } = m.useModule(MigrateGraphPaymentsModule)
  const { PaymentsEscrow, PaymentsEscrowImplementation } = m.useModule(MigratePaymentsEscrowModule)
  const { GraphTallyCollector } = m.useModule(MigrateGraphTallyCollectorModule)
  const { RecurringCollector } = m.useModule(MigrateRecurringCollectorModule)

  return {
    HorizonStaking,
    HorizonStakingImplementation,
    GraphPayments,
    GraphPaymentsImplementation,
    PaymentsEscrow,
    PaymentsEscrowImplementation,
    GraphTallyCollector,
    RecurringCollector,
  }
})
