import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import RecurringCollectorArtifact from '../../../build/contracts/contracts/payments/collectors/RecurringCollector.sol/RecurringCollector.json'
import GraphPeripheryModule from '../periphery/periphery'
import { deployImplementation } from '../proxy/implementation'
import {
  deployTransparentUpgradeableProxy,
  upgradeTransparentUpgradeableProxy,
} from '../proxy/TransparentUpgradeableProxy'
import HorizonProxiesModule from './HorizonProxies'

export default buildModule('RecurringCollector', (m) => {
  const { Controller } = m.useModule(GraphPeripheryModule)

  const governor = m.getAccount(1)
  const revokeSignerThawingPeriod = m.getParameter('revokeSignerThawingPeriod')
  const eip712Name = m.getParameter('eip712Name')
  const eip712Version = m.getParameter('eip712Version')

  // Deploy proxy
  const { Proxy: RecurringCollectorProxy, ProxyAdmin: RecurringCollectorProxyAdmin } =
    deployTransparentUpgradeableProxy(m, {
      name: 'RecurringCollector',
      artifact: RecurringCollectorArtifact,
    })

  // Deploy implementation - requires periphery and proxies to be registered in the controller
  const RecurringCollectorImplementation = deployImplementation(
    m,
    {
      name: 'RecurringCollector',
      artifact: RecurringCollectorArtifact,
      constructorArgs: [Controller, revokeSignerThawingPeriod],
    },
    { after: [GraphPeripheryModule, HorizonProxiesModule] },
  )

  // Upgrade proxy to implementation contract
  const RecurringCollector = upgradeTransparentUpgradeableProxy(
    m,
    RecurringCollectorProxyAdmin,
    RecurringCollectorProxy,
    RecurringCollectorImplementation,
    {
      name: 'RecurringCollector',
      artifact: RecurringCollectorArtifact,
      initArgs: [eip712Name, eip712Version],
    },
  )

  m.call(RecurringCollectorProxyAdmin, 'transferOwnership', [governor], { after: [RecurringCollector] })

  return { RecurringCollector, RecurringCollectorProxyAdmin, RecurringCollectorImplementation }
})
