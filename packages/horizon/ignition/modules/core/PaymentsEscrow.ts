import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import PaymentsEscrowArtifact from '../../../build/contracts/contracts/payments/PaymentsEscrow.sol/PaymentsEscrow.json'
import type { buildPeripheryModule } from '../periphery/periphery'
import { deployImplementation } from '../proxy/implementation'
import { upgradeTransparentUpgradeableProxy } from '../proxy/TransparentUpgradeableProxy'
import type { buildHorizonProxiesModule } from './HorizonProxies'

export function buildPaymentsEscrowModule(
  GraphPeripheryModule: ReturnType<typeof buildPeripheryModule>,
  HorizonProxiesModule: ReturnType<typeof buildHorizonProxiesModule>,
) {
  return buildModule('PaymentsEscrow', (m) => {
    const { Controller } = m.useModule(GraphPeripheryModule)
    const { PaymentsEscrowProxyAdmin, PaymentsEscrowProxy } = m.useModule(HorizonProxiesModule)

    const governor = m.getParameter('governor')
    const withdrawEscrowThawingPeriod = m.getParameter('withdrawEscrowThawingPeriod')

    // Deploy PaymentsEscrow implementation - requires periphery and proxies to be registered in the controller
    const PaymentsEscrowImplementation = deployImplementation(
      m,
      {
        name: 'PaymentsEscrow',
        artifact: PaymentsEscrowArtifact,
        constructorArgs: [Controller, withdrawEscrowThawingPeriod],
      },
      { after: [GraphPeripheryModule, HorizonProxiesModule] },
    )

    // Upgrade proxy to implementation contract
    const PaymentsEscrow = upgradeTransparentUpgradeableProxy(
      m,
      PaymentsEscrowProxyAdmin,
      PaymentsEscrowProxy,
      PaymentsEscrowImplementation,
      {
        name: 'PaymentsEscrow',
        artifact: PaymentsEscrowArtifact,
        initArgs: [],
      },
    )

    m.call(PaymentsEscrowProxyAdmin, 'transferOwnership', [governor], { after: [PaymentsEscrow] })

    return { PaymentsEscrow, PaymentsEscrowProxyAdmin, PaymentsEscrowImplementation }
  })
}
