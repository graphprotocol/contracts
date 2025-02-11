import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphPeripheryModule, { MigratePeripheryModule } from '../periphery/periphery'
import HorizonProxiesModule from './HorizonProxies'

import GraphTallyCollectorArtifact from '../../../build/contracts/contracts/payments/collectors/GraphTallyCollector.sol/GraphTallyCollector.json'

export default buildModule('GraphTallyCollector', (m) => {
  const { Controller } = m.useModule(GraphPeripheryModule)

  const name = m.getParameter('eip712Name')
  const version = m.getParameter('eip712Version')
  const revokeSignerThawingPeriod = m.getParameter('revokeSignerThawingPeriod')

  const GraphTallyCollector = m.contract(
    'GraphTallyCollector',
    GraphTallyCollectorArtifact,
    [name, version, Controller, revokeSignerThawingPeriod],
    { after: [GraphPeripheryModule, HorizonProxiesModule] },
  )

  return { GraphTallyCollector }
})

// Note that this module requires MigrateHorizonProxiesGovernorModule to be executed first
// The dependency is not made explicit to support the production workflow where the governor is a
// multisig owned by the Graph Council.
// For testnet, the dependency can be made explicit by having a parent module establish it.
export const MigrateGraphTallyCollectorModule = buildModule('GraphTallyCollector', (m) => {
  const { Controller } = m.useModule(MigratePeripheryModule)

  const name = m.getParameter('eip712Name')
  const version = m.getParameter('eip712Version')
  const revokeSignerThawingPeriod = m.getParameter('revokeSignerThawingPeriod')

  const GraphTallyCollector = m.contract(
    'GraphTallyCollector',
    GraphTallyCollectorArtifact,
    [name, version, Controller, revokeSignerThawingPeriod],
  )

  return { GraphTallyCollector }
})
