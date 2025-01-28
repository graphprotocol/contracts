import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import { MigrateHorizonProxiesGovernorModule } from '../core/HorizonProxies'

export default buildModule('GraphHorizon_Migrate_2', (m) => {
  const {
    GraphPaymentsProxy,
    PaymentsEscrowProxy,
    GraphPaymentsProxyAdmin,
    PaymentsEscrowProxyAdmin,
  } = m.useModule(MigrateHorizonProxiesGovernorModule)

  return {
    GraphPaymentsProxy,
    PaymentsEscrowProxy,
    GraphPaymentsProxyAdmin,
    PaymentsEscrowProxyAdmin,
  }
})
