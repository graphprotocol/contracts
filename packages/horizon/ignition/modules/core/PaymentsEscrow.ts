import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphPeripheryModule from '../periphery'
import HorizonProxiesModule from './HorizonProxies'

import PaymentsEscrowArtifact from '../../../build/contracts/contracts/payments/PaymentsEscrow.sol/PaymentsEscrow.json'

// TODO: transfer ownership of ProxyAdmin???
export default buildModule('PaymentsEscrow', (m) => {
  const { Controller } = m.useModule(GraphPeripheryModule)
  const { PaymentsEscrowProxyAdmin, PaymentsEscrowProxy } = m.useModule(HorizonProxiesModule)

  const withdrawEscrowThawingPeriod = m.getParameter('withdrawEscrowThawingPeriod')

  // Deploy PaymentsEscrow implementation
  const PaymentsEscrowImplementation = m.contract('PaymentsEscrow',
    PaymentsEscrowArtifact,
    [Controller, withdrawEscrowThawingPeriod],
    {
      after: [GraphPeripheryModule, HorizonProxiesModule],
    },
  )

  // Upgrade proxy to implementation contract
  m.call(PaymentsEscrowProxyAdmin, 'upgradeAndCall', [PaymentsEscrowProxy, PaymentsEscrowImplementation, m.encodeFunctionCall(PaymentsEscrowImplementation, 'initialize', [])])

  // Load contract with implementation ABI
  const PaymentsEscrow = m.contractAt('PaymentsEscrow', PaymentsEscrowArtifact, PaymentsEscrowProxy, { id: 'PaymentsEscrow_Instance' })

  return { PaymentsEscrow, PaymentsEscrowImplementation }
})
