import GraphProxyAdminArtifact from '@graphprotocol/contracts-7.3.0/artifacts/contracts/upgrades/GraphProxyAdmin.sol/GraphProxyAdmin.json'
import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

export default buildModule('GraphProxyAdmin', (m) => {
  const governor = m.getParameter('governor')

  const GraphProxyAdmin = m.contract('GraphProxyAdmin', GraphProxyAdminArtifact)
  m.call(GraphProxyAdmin, 'transferOwnership', [governor])

  return { GraphProxyAdmin }
})

export const MigrateGraphProxyAdminModule = buildModule('GraphProxyAdmin', (m) => {
  const graphProxyAdminAddress = m.getParameter('graphProxyAdminAddress')

  const GraphProxyAdmin = m.contractAt('GraphProxyAdmin', GraphProxyAdminArtifact, graphProxyAdminAddress)

  return { GraphProxyAdmin }
})
