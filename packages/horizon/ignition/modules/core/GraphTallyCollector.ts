import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphTallyCollectorArtifact from '../../../build/contracts/contracts/payments/collectors/GraphTallyCollector.sol/GraphTallyCollector.json'
import GraphPeripheryModule from '../periphery/periphery'
import HorizonProxiesModule from './HorizonProxies'

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
