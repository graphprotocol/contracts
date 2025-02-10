import { buildModule } from '@nomicfoundation/ignition-core'

import { deployWithGraphProxy } from '../proxy/GraphProxy'

import ControllerModule from '../periphery/Controller'
import GraphProxyAdminModule from '../periphery/GraphProxyAdmin'

import GraphTokenGatewayArtifact from '@graphprotocol/contracts/build/contracts/contracts/l2/gateway/L2GraphTokenGateway.sol/L2GraphTokenGateway.json'

export default buildModule('L2GraphTokenGateway', (m) => {
  const { Controller } = m.useModule(ControllerModule)
  const { GraphProxyAdmin } = m.useModule(GraphProxyAdminModule)

  const pauseGuardian = m.getParameter('pauseGuardian')

  const GraphTokenGateway = deployWithGraphProxy(m, GraphProxyAdmin, {
    name: 'L2GraphTokenGateway',
    artifact: GraphTokenGatewayArtifact,
    initArgs: [Controller],
  })
  m.call(GraphTokenGateway, 'setPauseGuardian', [pauseGuardian])

  return { GraphTokenGateway }
})

export const MigrateGraphTokenGatewayModule = buildModule('L2GraphTokenGateway', (m) => {
  const graphTokenGatewayAddress = m.getParameter('graphTokenGatewayAddress')

  const GraphTokenGateway = m.contractAt('L2GraphTokenGateway', GraphTokenGatewayArtifact, graphTokenGatewayAddress)

  return { GraphTokenGateway }
})
