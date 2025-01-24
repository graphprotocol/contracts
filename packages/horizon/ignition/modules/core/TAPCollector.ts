import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphPeripheryModule, { MigratePeripheryModule } from '../periphery/periphery'
import HorizonProxiesModule, { MigrateHorizonProxiesModule } from './HorizonProxies'

import TAPCollectorArtifact from '../../../build/contracts/contracts/payments/collectors/TAPCollector.sol/TAPCollector.json'

export default buildModule('TAPCollector', (m) => {
  const { Controller } = m.useModule(GraphPeripheryModule)

  const name = m.getParameter('eip712Name')
  const version = m.getParameter('eip712Version')
  const revokeSignerThawingPeriod = m.getParameter('revokeSignerThawingPeriod')

  const TAPCollector = m.contract(
    'TAPCollector',
    TAPCollectorArtifact,
    [name, version, Controller, revokeSignerThawingPeriod],
    { after: [GraphPeripheryModule, HorizonProxiesModule] },
  )

  return { TAPCollector }
})

export const MigrateTAPCollectorModule = buildModule('TAPCollector', (m) => {
  const { Controller } = m.useModule(MigratePeripheryModule)

  const name = m.getParameter('eip712Name')
  const version = m.getParameter('eip712Version')
  const revokeSignerThawingPeriod = m.getParameter('revokeSignerThawingPeriod')

  const TAPCollector = m.contract(
    'TAPCollector',
    TAPCollectorArtifact,
    [name, version, Controller, revokeSignerThawingPeriod],
    { after: [MigrateHorizonProxiesModule] },
  )

  return { TAPCollector }
})
