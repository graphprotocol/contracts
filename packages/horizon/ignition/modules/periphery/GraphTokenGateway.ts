import { buildModule } from '@nomicfoundation/ignition-core'

import { deployWithGraphProxy } from '../lib/proxy'

import ControllerModule from '../periphery/Controller'
import GraphTokenGatewayArtifact from '@graphprotocol/contracts/build/contracts/contracts/l2/gateway/L2GraphTokenGateway.sol/L2GraphTokenGateway.json'

export default buildModule('GraphTokenGateway', (m) => {
  const { Controller } = m.useModule(ControllerModule)

  const pauseGuardian = m.getParameter('pauseGuardian')

  const { instance: GraphTokenGateway } = deployWithGraphProxy(m, {
    name: 'GraphTokenGateway',
    artifact: GraphTokenGatewayArtifact,
    args: [Controller],
  })

  m.call(GraphTokenGateway, 'setPauseGuardian', [pauseGuardian])

  return { GraphTokenGateway }
})
