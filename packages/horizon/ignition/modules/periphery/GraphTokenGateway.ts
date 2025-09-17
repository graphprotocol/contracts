import GraphTokenGatewayArtifact from '@graphprotocol/contracts/artifacts/contracts/l2/gateway/L2GraphTokenGateway.sol/L2GraphTokenGateway.json'
import { buildModule } from '@nomicfoundation/ignition-core'

import ControllerModule from '../periphery/Controller'
import GraphProxyAdminModule from '../periphery/GraphProxyAdmin'
import { deployWithGraphProxy } from '../proxy/GraphProxy'

export default buildModule('L2GraphTokenGateway', (m) => {
  const { Controller } = m.useModule(ControllerModule)
  const { GraphProxyAdmin } = m.useModule(GraphProxyAdminModule)

  const pauseGuardian = m.getParameter('pauseGuardian')

  const { proxy: L2GraphTokenGateway, implementation: L2GraphTokenGatewayImplementation } = deployWithGraphProxy(
    m,
    GraphProxyAdmin,
    {
      name: 'L2GraphTokenGateway',
      artifact: GraphTokenGatewayArtifact,
      initArgs: [Controller],
    },
  )
  m.call(L2GraphTokenGateway, 'setPauseGuardian', [pauseGuardian])

  return { L2GraphTokenGateway, L2GraphTokenGatewayImplementation }
})

export const MigrateGraphTokenGatewayModule = buildModule('L2GraphTokenGateway', (m) => {
  const graphTokenGatewayAddress = m.getParameter('graphTokenGatewayAddress')
  const graphTokenGatewayImplementationAddress = m.getParameter('graphTokenGatewayImplementationAddress')

  const L2GraphTokenGateway = m.contractAt('L2GraphTokenGateway', GraphTokenGatewayArtifact, graphTokenGatewayAddress)
  const L2GraphTokenGatewayImplementation = m.contractAt(
    'L2GraphTokenGatewayAddressBook',
    GraphTokenGatewayArtifact,
    graphTokenGatewayImplementationAddress,
  )

  return { L2GraphTokenGateway, L2GraphTokenGatewayImplementation }
})
