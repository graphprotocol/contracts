import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphPaymentsModule from './GraphPayments'
import HorizonStakingModule from './HorizonStaking'
import PaymentsEscrowModule from './PaymentsEscrow'
import TAPCollectorModule from './TAPCollector'

export default buildModule('GraphHorizon_Core', (m) => {
  const { HorizonStaking } = m.useModule(HorizonStakingModule)
  const { GraphPayments } = m.useModule(GraphPaymentsModule)
  const { PaymentsEscrow } = m.useModule(PaymentsEscrowModule)
  const { TAPCollector } = m.useModule(TAPCollectorModule)

  return { HorizonStaking, GraphPayments, PaymentsEscrow, TAPCollector }
})
