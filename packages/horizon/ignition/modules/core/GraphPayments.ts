import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import { deployImplementation } from '../proxy/implementation'
import { upgradeTransparentUpgradeableProxy } from '../proxy/TransparentUpgradeableProxy'

import GraphPeripheryModule, { MigratePeripheryModule } from '../periphery/periphery'
import HorizonProxiesModule, { MigrateHorizonProxiesDeployerModule } from './HorizonProxies'

import GraphPaymentsArtifact from '../../../build/contracts/contracts/payments/GraphPayments.sol/GraphPayments.json'

export default buildModule('GraphPayments', (m) => {
  const { Controller } = m.useModule(GraphPeripheryModule)
  const { GraphPaymentsProxyAdmin, GraphPaymentsProxy } = m.useModule(HorizonProxiesModule)

  const governor = m.getParameter('governor')
  const protocolPaymentCut = m.getParameter('protocolPaymentCut')

  // Deploy GraphPayments implementation - requires periphery and proxies to be registered in the controller
  const GraphPaymentsImplementation = deployImplementation(m, {
    name: 'GraphPayments',
    artifact: GraphPaymentsArtifact,
    constructorArgs: [Controller, protocolPaymentCut],
  }, { after: [GraphPeripheryModule, HorizonProxiesModule] })

  // Upgrade proxy to implementation contract
  const GraphPayments = upgradeTransparentUpgradeableProxy(m,
    GraphPaymentsProxyAdmin,
    GraphPaymentsProxy,
    GraphPaymentsImplementation, {
      name: 'GraphPayments',
      artifact: GraphPaymentsArtifact,
      initArgs: [],
    })

  m.call(GraphPaymentsProxyAdmin, 'transferOwnership', [governor], { after: [GraphPayments] })

  return { GraphPayments, GraphPaymentsProxyAdmin, GraphPaymentsImplementation }
})

// Note that this module requires MigrateHorizonProxiesGovernorModule to be executed first
// The dependency is not made explicit to support the production workflow where the governor is a
// multisig owned by the Graph Council.
// For testnet, the dependency can be made explicit by having a parent module establish it.
export const MigrateGraphPaymentsModule = buildModule('GraphPayments', (m) => {
  const { GraphPaymentsProxyAdmin, GraphPaymentsProxy } = m.useModule(MigrateHorizonProxiesDeployerModule)
  const { Controller } = m.useModule(MigratePeripheryModule)

  const governor = m.getParameter('governor')
  const protocolPaymentCut = m.getParameter('protocolPaymentCut')

  // Deploy GraphPayments implementation
  const GraphPaymentsImplementation = deployImplementation(m, {
    name: 'GraphPayments',
    artifact: GraphPaymentsArtifact,
    constructorArgs: [Controller, protocolPaymentCut],
  })

  // Upgrade proxy to implementation contract
  const GraphPayments = upgradeTransparentUpgradeableProxy(m,
    GraphPaymentsProxyAdmin,
    GraphPaymentsProxy,
    GraphPaymentsImplementation, {
      name: 'GraphPayments',
      artifact: GraphPaymentsArtifact,
      initArgs: [],
    })

  m.call(GraphPaymentsProxyAdmin, 'transferOwnership', [governor], { after: [GraphPayments] })

  return { GraphPayments, GraphPaymentsProxyAdmin, GraphPaymentsImplementation }
})
