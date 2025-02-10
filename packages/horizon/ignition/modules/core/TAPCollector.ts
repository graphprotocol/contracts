import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphPeripheryModule, { MigratePeripheryModule } from '../periphery/periphery'
import HorizonProxiesModule from './HorizonProxies'

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

// Note that this module requires MigrateHorizonProxiesGovernorModule to be executed first
// The dependency is not made explicit to support the production workflow where the governor is a
// multisig owned by the Graph Council.
// For testnet, the dependency can be made explicit by having a parent module establish it.
export const MigrateTAPCollectorModule = buildModule('TAPCollector', (m) => {
  const { Controller } = m.useModule(MigratePeripheryModule)

  const name = m.getParameter('eip712Name')
  const version = m.getParameter('eip712Version')
  const revokeSignerThawingPeriod = m.getParameter('revokeSignerThawingPeriod')

  const TAPCollector = m.contract(
    'TAPCollector',
    TAPCollectorArtifact,
    [name, version, Controller, revokeSignerThawingPeriod],
  )

  return { TAPCollector }
})
