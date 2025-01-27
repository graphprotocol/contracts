import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import { deployImplementation } from '../proxy/implementation'
import { upgradeTransparentUpgradeableProxyNoLoad } from '../proxy/TransparentUpgradeableProxy'

import GraphPeripheryModule, { MigratePeripheryModule } from '../periphery/periphery'
import HorizonProxiesModule, { MigrateHorizonProxiesModule } from './HorizonProxies'

import GraphPaymentsArtifact from '../../../build/contracts/contracts/payments/GraphPayments.sol/GraphPayments.json'

export default buildModule('GraphPayments', (m) => {
  const { Controller } = m.useModule(GraphPeripheryModule)
  const { GraphPaymentsProxyAdmin, GraphPaymentsProxy } = m.useModule(HorizonProxiesModule)

  const protocolPaymentCut = m.getParameter('protocolPaymentCut')

  // Deploy GraphPayments implementation - requires periphery and proxies to be registered in the controller
  const GraphPaymentsImplementation = deployImplementation(m, {
    name: 'GraphPayments',
    artifact: GraphPaymentsArtifact,
    constructorArgs: [Controller, protocolPaymentCut],
  }, { after: [GraphPeripheryModule, HorizonProxiesModule] })

  // Upgrade proxy to implementation contract
  const GraphPayments = upgradeTransparentUpgradeableProxyNoLoad(m,
    GraphPaymentsProxyAdmin,
    GraphPaymentsProxy,
    GraphPaymentsImplementation, {
      name: 'GraphPayments',
      artifact: GraphPaymentsArtifact,
      initArgs: [],
    })

  return { GraphPayments, GraphPaymentsProxyAdmin }
})

export const MigrateGraphPaymentsModule = buildModule('GraphPayments', (m) => {
  const { GraphPaymentsProxyAdmin, GraphPaymentsProxy } = m.useModule(MigrateHorizonProxiesModule)
  const { Controller } = m.useModule(MigratePeripheryModule)

  const protocolPaymentCut = m.getParameter('protocolPaymentCut')

  // Deploy GraphPayments implementation
  const GraphPaymentsImplementation = deployImplementation(m, {
    name: 'GraphPayments',
    artifact: GraphPaymentsArtifact,
    constructorArgs: [Controller, protocolPaymentCut],
  }, { after: [MigrateHorizonProxiesModule] })

  // Upgrade proxy to implementation contract
  const GraphPayments = upgradeTransparentUpgradeableProxyNoLoad(m,
    GraphPaymentsProxyAdmin,
    GraphPaymentsProxy,
    GraphPaymentsImplementation, {
      name: 'GraphPayments',
      artifact: GraphPaymentsArtifact,
      initArgs: [],
    })

  return { GraphPayments, GraphPaymentsProxyAdmin }
})
