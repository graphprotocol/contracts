import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import RecurringCollectorArtifact from '../../../build/contracts/contracts/payments/collectors/RecurringCollector.sol/RecurringCollector.json'
import GraphPeripheryModule from '../periphery/periphery'
import { deployImplementation } from '../proxy/implementation'
import { upgradeTransparentUpgradeableProxy } from '../proxy/TransparentUpgradeableProxy'
import HorizonProxiesModule from './HorizonProxies'

export default buildModule('RecurringCollector', (m) => {
  const { Controller } = m.useModule(GraphPeripheryModule)
  const { RecurringCollectorProxyAdmin, RecurringCollectorProxy } = m.useModule(HorizonProxiesModule)

  const governor = m.getAccount(1)

  // Deploy RecurringCollector implementation - requires periphery and proxies to be registered in the controller
  const RecurringCollectorImplementation = deployImplementation(
    m,
    {
      name: 'RecurringCollector',
      artifact: RecurringCollectorArtifact,
      constructorArgs: [Controller],
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
      initArgs: [],
    },
  )

  m.call(RecurringCollectorProxyAdmin, 'transferOwnership', [governor], { after: [RecurringCollector] })

  return { RecurringCollector, RecurringCollectorProxyAdmin, RecurringCollectorImplementation }
})
