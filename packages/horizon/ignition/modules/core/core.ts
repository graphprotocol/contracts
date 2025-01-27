import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphPaymentsModule, { MigrateGraphPaymentsModule } from './GraphPayments'
import HorizonStakingModule, { MigrateHorizonStakingModule } from './HorizonStaking'
import PaymentsEscrowModule, { MigratePaymentsEscrowModule } from './PaymentsEscrow'
import TAPCollectorModule, { MigrateTAPCollectorModule } from './TAPCollector'

export default buildModule('GraphHorizon_Core', (m) => {
  const { HorizonStaking } = m.useModule(HorizonStakingModule)
  const { GraphPayments, GraphPaymentsProxyAdmin } = m.useModule(GraphPaymentsModule)
  const { PaymentsEscrow, PaymentsEscrowProxyAdmin } = m.useModule(PaymentsEscrowModule)
  const { TAPCollector } = m.useModule(TAPCollectorModule)

  return { HorizonStaking, GraphPayments, PaymentsEscrow, TAPCollector, GraphPaymentsProxyAdmin, PaymentsEscrowProxyAdmin }
})

export const MigrateHorizonCoreModule = buildModule('GraphHorizon_Core', (m) => {
  const { HorizonStaking } = m.useModule(MigrateHorizonStakingModule)
  const { GraphPayments } = m.useModule(MigrateGraphPaymentsModule)
  const { PaymentsEscrow } = m.useModule(MigratePaymentsEscrowModule)
  const { TAPCollector } = m.useModule(MigrateTAPCollectorModule)

  return { HorizonStaking, GraphPayments, PaymentsEscrow, TAPCollector }
})
