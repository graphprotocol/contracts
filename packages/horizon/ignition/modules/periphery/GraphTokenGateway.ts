import { buildModule } from '@nomicfoundation/ignition-core'

import { deployWithGraphProxy } from '../proxy/GraphProxy'

import ControllerModule from '../periphery/Controller'
import GraphProxyAdminModule from '../periphery/GraphProxyAdmin'

import GraphTokenGatewayArtifact from '@graphprotocol/contracts/build/contracts/contracts/l2/gateway/L2GraphTokenGateway.sol/L2GraphTokenGateway.json'

export default buildModule('L2GraphTokenGateway', (m) => {
  const { Controller } = m.useModule(ControllerModule)
  const { GraphProxyAdmin } = m.useModule(GraphProxyAdminModule)

  const pauseGuardian = m.getParameter('pauseGuardian')

  const { proxy: L2GraphTokenGateway, implementation: L2GraphTokenGatewayImplementation } = deployWithGraphProxy(m, GraphProxyAdmin, {
    name: 'L2GraphTokenGateway',
    artifact: GraphTokenGatewayArtifact,
    initArgs: [Controller],
  })
  m.call(L2GraphTokenGateway, 'setPauseGuardian', [pauseGuardian])

  return { L2GraphTokenGateway, L2GraphTokenGatewayImplementation }
})

export const MigrateGraphTokenGatewayModule = buildModule('L2GraphTokenGateway', (m) => {
  const graphTokenGatewayAddress = m.getParameter('graphTokenGatewayAddress')

  const L2GraphTokenGateway = m.contractAt('L2GraphTokenGateway', GraphTokenGatewayArtifact, graphTokenGatewayAddress)

  return { L2GraphTokenGateway }
})
