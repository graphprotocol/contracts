import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphPeripheryModule from '../periphery'
import HorizonProxiesModule from './HorizonProxies'

import GraphPaymentsArtifact from '../../../build/contracts/contracts/payments/GraphPayments.sol/GraphPayments.json'

// TODO: transfer ownership of ProxyAdmin???
export default buildModule('GraphPayments', (m) => {
  const { Controller } = m.useModule(GraphPeripheryModule)
  const { GraphPaymentsProxyAdmin, GraphPaymentsProxy } = m.useModule(HorizonProxiesModule)

  const protocolPaymentCut = m.getParameter('protocolPaymentCut')

  // Deploy GraphPayments implementation
  const GraphPaymentsImplementation = m.contract('GraphPayments',
    GraphPaymentsArtifact,
    [Controller, protocolPaymentCut],
    {
      after: [GraphPeripheryModule, HorizonProxiesModule],
    },
  )

  // Upgrade proxy to implementation contract
  m.call(GraphPaymentsProxyAdmin, 'upgradeAndCall', [GraphPaymentsProxy, GraphPaymentsImplementation, m.encodeFunctionCall(GraphPaymentsImplementation, 'initialize', [])])

  // Load contract with implementation ABI
  const GraphPayments = m.contractAt('GraphPayments', GraphPaymentsArtifact, GraphPaymentsProxy, { id: 'GraphPayments_Instance' })

  return { GraphPayments, GraphPaymentsImplementation }
})
