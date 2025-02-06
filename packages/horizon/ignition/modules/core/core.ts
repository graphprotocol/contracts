import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphPaymentsModule, { MigrateGraphPaymentsModule } from './GraphPayments'
import HorizonStakingModule, { MigrateHorizonStakingDeployerModule } from './HorizonStaking'
import PaymentsEscrowModule, { MigratePaymentsEscrowModule } from './PaymentsEscrow'
import TAPCollectorModule, { MigrateTAPCollectorModule } from './TAPCollector'

export default buildModule('GraphHorizon_Core', (m) => {
  const { HorizonStaking } = m.useModule(HorizonStakingModule)
  const { GraphPayments } = m.useModule(GraphPaymentsModule)
  const { PaymentsEscrow } = m.useModule(PaymentsEscrowModule)
  const { TAPCollector } = m.useModule(TAPCollectorModule)

  return { HorizonStaking, GraphPayments, PaymentsEscrow, TAPCollector }
})

export const MigrateHorizonCoreModule = buildModule('GraphHorizon_Core', (m) => {
  const { HorizonStakingProxy: HorizonStaking, HorizonStakingImplementation } = m.useModule(MigrateHorizonStakingDeployerModule)
  const { GraphPayments } = m.useModule(MigrateGraphPaymentsModule)
  const { PaymentsEscrow } = m.useModule(MigratePaymentsEscrowModule)
  const { TAPCollector } = m.useModule(MigrateTAPCollectorModule)

  return { HorizonStaking, HorizonStakingImplementation, GraphPayments, PaymentsEscrow, TAPCollector }
})
