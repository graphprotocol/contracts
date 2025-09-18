import GraphProxyAdminArtifact from '@graphprotocol/contracts/artifacts/contracts/upgrades/GraphProxyAdmin.sol/GraphProxyAdmin.json'
import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

export default buildModule('GraphProxyAdmin', (m) => {
  const governor = m.getAccount(1)

  const GraphProxyAdmin = m.contract('GraphProxyAdmin', GraphProxyAdminArtifact)
  m.call(GraphProxyAdmin, 'transferOwnership', [governor])

  return { GraphProxyAdmin }
})

export const MigrateGraphProxyAdminModule = buildModule('GraphProxyAdmin', (m) => {
  const graphProxyAdminAddress = m.getParameter('graphProxyAdminAddress')

  const GraphProxyAdmin = m.contractAt('GraphProxyAdmin', GraphProxyAdminArtifact, graphProxyAdminAddress)

  return { GraphProxyAdmin }
})
