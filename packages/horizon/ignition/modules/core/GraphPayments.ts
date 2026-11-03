import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphPaymentsArtifact from '../../../build/contracts/contracts/payments/GraphPayments.sol/GraphPayments.json'
import GraphPeripheryModule from '../periphery/periphery'
import { deployImplementation } from '../proxy/implementation'
import { upgradeTransparentUpgradeableProxy } from '../proxy/TransparentUpgradeableProxy'
import HorizonProxiesModule from './HorizonProxies'

export default buildModule('GraphPayments', (m) => {
  const { Controller } = m.useModule(GraphPeripheryModule)
  const { GraphPaymentsProxyAdmin, GraphPaymentsProxy } = m.useModule(HorizonProxiesModule)

  const governor = m.getParameter('governor')
  const protocolPaymentCut = m.getParameter('protocolPaymentCut')

  // Deploy GraphPayments implementation - requires periphery and proxies to be registered in the controller
  const GraphPaymentsImplementation = deployImplementation(
    m,
    {
      name: 'GraphPayments',
      artifact: GraphPaymentsArtifact,
      constructorArgs: [Controller, protocolPaymentCut],
    },
    { after: [GraphPeripheryModule, HorizonProxiesModule] },
  )

  // Upgrade proxy to implementation contract
  const GraphPayments = upgradeTransparentUpgradeableProxy(
    m,
    GraphPaymentsProxyAdmin,
    GraphPaymentsProxy,
    GraphPaymentsImplementation,
    {
      name: 'GraphPayments',
      artifact: GraphPaymentsArtifact,
      initArgs: [],
    },
  )

  m.call(GraphPaymentsProxyAdmin, 'transferOwnership', [governor], { after: [GraphPayments] })

  return { GraphPayments, GraphPaymentsProxyAdmin, GraphPaymentsImplementation }
})
