import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphPaymentsModule from './GraphPayments'
import GraphTallyCollectorModule from './GraphTallyCollector'
import HorizonStakingModule from './HorizonStaking'
import PaymentsEscrowModule from './PaymentsEscrow'
import RecurringCollectorModule from './RecurringCollector'

export default buildModule('GraphHorizon_Core', (m) => {
  const { HorizonStaking, HorizonStakingImplementation } = m.useModule(HorizonStakingModule)
  const { GraphPaymentsProxyAdmin, GraphPayments, GraphPaymentsImplementation } = m.useModule(GraphPaymentsModule)
  const { PaymentsEscrowProxyAdmin, PaymentsEscrow, PaymentsEscrowImplementation } = m.useModule(PaymentsEscrowModule)
  const { GraphTallyCollector } = m.useModule(GraphTallyCollectorModule)
  const { RecurringCollectorProxyAdmin, RecurringCollector, RecurringCollectorImplementation } =
    m.useModule(RecurringCollectorModule)

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
    RecurringCollectorProxyAdmin,
    RecurringCollector,
    RecurringCollectorImplementation,
  }
})
