import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphPaymentsModule from './core/GraphPayments'
import HorizonStakingModule from './core/HorizonStaking'
import PaymentsEscrowModule from './core/PaymentsEscrow'
import TAPCollectorModule from './core/TAPCollector'

export default buildModule('GraphHorizon_Core', (m) => {
  const { HorizonStaking } = m.useModule(HorizonStakingModule)
  const { GraphPayments } = m.useModule(GraphPaymentsModule)
  const { PaymentsEscrow } = m.useModule(PaymentsEscrowModule)
  const { TAPCollector } = m.useModule(TAPCollectorModule)

  return { HorizonStaking, GraphPayments, PaymentsEscrow, TAPCollector }
})
