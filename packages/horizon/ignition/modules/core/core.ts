import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import type { buildPeripheryModule } from '../periphery/periphery'
import { buildGraphPaymentsModule } from './GraphPayments'
import { buildGraphTallyCollectorModule } from './GraphTallyCollector'
import type { buildHorizonProxiesModule } from './HorizonProxies'
import { buildHorizonStakingModule } from './HorizonStaking'
import { buildPaymentsEscrowModule } from './PaymentsEscrow'
import { buildRecurringCollectorModule } from './RecurringCollector'

export function buildCoreModule(
  GraphPeripheryModule: ReturnType<typeof buildPeripheryModule>,
  HorizonProxiesModule: ReturnType<typeof buildHorizonProxiesModule>,
) {
  const HorizonStakingModule = buildHorizonStakingModule(GraphPeripheryModule, HorizonProxiesModule)
  const GraphPaymentsModule = buildGraphPaymentsModule(GraphPeripheryModule, HorizonProxiesModule)
  const PaymentsEscrowModule = buildPaymentsEscrowModule(GraphPeripheryModule, HorizonProxiesModule)
  const GraphTallyCollectorModule = buildGraphTallyCollectorModule(GraphPeripheryModule, HorizonProxiesModule)
  const RecurringCollectorModule = buildRecurringCollectorModule(GraphPeripheryModule, HorizonProxiesModule)

  return buildModule('GraphHorizon_Core', (m) => {
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
}
