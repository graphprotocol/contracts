import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphProxyAdminArtifact from '@graphprotocol/contracts/build/contracts/contracts/upgrades/GraphProxyAdmin.sol/GraphProxyAdmin.json'

// TODO: Ownership transfer is a two step process, the new owner needs to accept it by calling acceptOwnership
export default buildModule('GraphProxyAdmin', (m) => {
  const governor = m.getParameter('governor')
  const GraphProxyAdmin = m.contract('GraphProxyAdmin', GraphProxyAdminArtifact)

  m.call(GraphProxyAdmin, 'transferOwnership', [governor])

  return { GraphProxyAdmin }
})
