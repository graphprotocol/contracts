import GraphProxyAdminArtifact from '@graphprotocol/graph-core/artifacts/contracts/upgrades/GraphProxyAdmin.sol/GraphProxyAdmin.json'
import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

export default buildModule('GraphProxyAdmin', (m) => {
  const governor = m.getParameter('governor')

  const GraphProxyAdmin = m.contract('GraphProxyAdmin', GraphProxyAdminArtifact)
  m.call(GraphProxyAdmin, 'transferOwnership', [governor])

  return { GraphProxyAdmin }
})
