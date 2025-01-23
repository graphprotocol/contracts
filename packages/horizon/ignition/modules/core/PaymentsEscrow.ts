import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import { deployImplementation } from '../proxy/implementation'
import { upgradeTransparentUpgradeableProxyNoLoad } from '../proxy/TransparentUpgradeableProxy'

import GraphPeripheryModule from '../periphery/periphery'
import HorizonProxiesModule from './HorizonProxies'

import PaymentsEscrowArtifact from '../../../build/contracts/contracts/payments/PaymentsEscrow.sol/PaymentsEscrow.json'

export default buildModule('PaymentsEscrow', (m) => {
  const { Controller } = m.useModule(GraphPeripheryModule)
  const { PaymentsEscrowProxyAdmin, PaymentsEscrowProxy } = m.useModule(HorizonProxiesModule)

  const withdrawEscrowThawingPeriod = m.getParameter('withdrawEscrowThawingPeriod')

  // Deploy PaymentsEscrow implementation - requires periphery and proxies to be registered in the controller
  const PaymentsEscrowImplementation = deployImplementation(m, {
    name: 'PaymentsEscrow',
    artifact: PaymentsEscrowArtifact,
    constructorArgs: [Controller, withdrawEscrowThawingPeriod],
  }, { after: [GraphPeripheryModule, HorizonProxiesModule] })

  // Upgrade proxy to implementation contract
  const PaymentsEscrow = upgradeTransparentUpgradeableProxyNoLoad(m,
    PaymentsEscrowProxyAdmin,
    PaymentsEscrowProxy,
    PaymentsEscrowImplementation, {
      name: 'PaymentsEscrow',
      artifact: PaymentsEscrowArtifact,
      initArgs: [],
    })

  return { PaymentsEscrow, PaymentsEscrowProxyAdmin }
})
