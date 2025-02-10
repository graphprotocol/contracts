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
    GraphPaymentsProxy,
    PaymentsEscrowProxy,
    GraphPaymentsProxyAdmin,
    PaymentsEscrowProxyAdmin,
  }
})
