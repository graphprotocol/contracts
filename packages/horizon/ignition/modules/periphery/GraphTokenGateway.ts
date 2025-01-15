import { buildModule } from '@nomicfoundation/ignition-core'

import { deployWithGraphProxy } from '../proxy/GraphProxy'

import ControllerModule from '../periphery/Controller'
import GraphTokenGatewayArtifact from '@graphprotocol/contracts/build/contracts/contracts/l2/gateway/L2GraphTokenGateway.sol/L2GraphTokenGateway.json'

export default buildModule('GraphTokenGateway', (m) => {
  const isMigrate = m.getParameter('isMigrate', false)

  let GraphTokenGateway
  if (isMigrate) {
    const graphTokenGatewayProxyAddress = m.getParameter('graphTokenGatewayProxyAddress')
    GraphTokenGateway = m.contractAt('GraphTokenGateway', GraphTokenGatewayArtifact, graphTokenGatewayProxyAddress)
  } else {
    const { Controller } = m.useModule(ControllerModule)

    const pauseGuardian = m.getParameter('pauseGuardian')

    GraphTokenGateway = deployWithGraphProxy(m, {
      name: 'GraphTokenGateway',
      artifact: GraphTokenGatewayArtifact,
      args: [Controller],
    }).instance
    m.call(GraphTokenGateway, 'setPauseGuardian', [pauseGuardian])
  }

  return { GraphTokenGateway }
})
