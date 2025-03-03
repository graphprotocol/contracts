import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import { MigrateHorizonProxiesDeployerModule } from '../core/HorizonProxies'

export default buildModule('GraphHorizon_Migrate_1', (m) => {
  const {
    GraphPaymentsProxy,
    PaymentsEscrowProxy,
    GraphPaymentsProxyAdmin,
    PaymentsEscrowProxyAdmin,
  } = m.useModule(MigrateHorizonProxiesDeployerModule)

  return {
    Transparent_Proxy_GraphPayments: GraphPaymentsProxy,
    Transparent_Proxy_PaymentsEscrow: PaymentsEscrowProxy,
    Transparent_ProxyAdmin_GraphPayments: GraphPaymentsProxyAdmin,
    Transparent_ProxyAdmin_PaymentsEscrow: PaymentsEscrowProxyAdmin,
  }
})
