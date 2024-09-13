import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphPeripheryModule from '../periphery'
import HorizonProxiesModule from './HorizonProxies'

// TODO: transfer ownership of ProxyAdmin???
export default buildModule('PaymentsEscrow', (m) => {
  const { Controller, PeripheryRegistered } = m.useModule(GraphPeripheryModule)
  const { PaymentsEscrowProxyAdmin, PaymentsEscrowProxy, HorizonRegistered } = m.useModule(HorizonProxiesModule)

  const revokeCollectorThawingPeriod = m.getParameter('revokeCollectorThawingPeriod')
  const withdrawEscrowThawingPeriod = m.getParameter('withdrawEscrowThawingPeriod')

  // Deploy PaymentsEscrow implementation
  const PaymentsEscrowImplementation = m.contract('PaymentsEscrow',
    [Controller, revokeCollectorThawingPeriod, withdrawEscrowThawingPeriod],
    {
      after: [PeripheryRegistered, HorizonRegistered],
    },
  )

  // Upgrade proxy to implementation contract
  m.call(PaymentsEscrowProxyAdmin, 'upgradeAndCall', [PaymentsEscrowProxy, PaymentsEscrowImplementation, m.encodeFunctionCall(PaymentsEscrowImplementation, 'initialize', [])])

  // Load contract with implementation ABI
  const PaymentsEscrow = m.contractAt('PaymentsEscrow', PaymentsEscrowProxy, { id: 'PaymentsEscrow_Instance' })

  return { PaymentsEscrow }
})
