import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphProxyAdminArtifact from '@graphprotocol/contracts/build/contracts/contracts/upgrades/GraphProxyAdmin.sol/GraphProxyAdmin.json'

export default buildModule('GraphProxyAdmin', (m) => {
  const isMigrate = m.getParameter('isMigrate', false)

  let GraphProxyAdmin
  if (isMigrate) {
    const graphProxyAdminAddress = m.getParameter('graphProxyAdminAddress')
    GraphProxyAdmin = m.contractAt('GraphProxyAdmin', GraphProxyAdminArtifact, graphProxyAdminAddress)
  } else {
    // TODO: Ownership transfer is a two step process, the new owner needs to accept it by calling acceptOwnership
    const governor = m.getParameter('governor')
    GraphProxyAdmin = m.contract('GraphProxyAdmin', GraphProxyAdminArtifact)

    m.call(GraphProxyAdmin, 'transferOwnership', [governor])
  }

  return { GraphProxyAdmin }
})
