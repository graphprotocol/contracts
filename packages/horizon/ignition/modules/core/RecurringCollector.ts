import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import RecurringCollectorArtifact from '../../../build/contracts/contracts/payments/collectors/RecurringCollector.sol/RecurringCollector.json'
import GraphPeripheryModule, { MigratePeripheryModule } from '../periphery/periphery'
import HorizonProxiesModule from './HorizonProxies'

export default buildModule('RecurringCollector', (m) => {
  const { Controller } = m.useModule(GraphPeripheryModule)

  const name = m.getParameter('eip712Name')
  const version = m.getParameter('eip712Version')
  const revokeSignerThawingPeriod = m.getParameter('revokeSignerThawingPeriod')

  const RecurringCollector = m.contract(
    'RecurringCollector',
    RecurringCollectorArtifact,
    [name, version, Controller, revokeSignerThawingPeriod],
    { after: [GraphPeripheryModule, HorizonProxiesModule] },
  )

  return { RecurringCollector }
})

// Note that this module requires MigrateHorizonProxiesGovernorModule to be executed first
// The dependency is not made explicit to support the production workflow where the governor is a
// multisig owned by the Graph Council.
// For testnet, the dependency can be made explicit by having a parent module establish it.
export const MigrateRecurringCollectorModule = buildModule('RecurringCollector', (m) => {
  const { Controller } = m.useModule(MigratePeripheryModule)

  const name = m.getParameter('eip712Name')
  const version = m.getParameter('eip712Version')
  const revokeSignerThawingPeriod = m.getParameter('revokeSignerThawingPeriod')

  const RecurringCollector = m.contract('RecurringCollector', RecurringCollectorArtifact, [
    name,
    version,
    Controller,
    revokeSignerThawingPeriod,
  ])

  return { RecurringCollector }
})
