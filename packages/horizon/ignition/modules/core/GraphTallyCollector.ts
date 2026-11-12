import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphTallyCollectorArtifact from '../../../build/contracts/contracts/payments/collectors/GraphTallyCollector.sol/GraphTallyCollector.json'
import type { buildPeripheryModule } from '../periphery/periphery'
import type { buildHorizonProxiesModule } from './HorizonProxies'

export function buildGraphTallyCollectorModule(
  GraphPeripheryModule: ReturnType<typeof buildPeripheryModule>,
  HorizonProxiesModule: ReturnType<typeof buildHorizonProxiesModule>,
) {
  return buildModule('GraphTallyCollector', (m) => {
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
}
