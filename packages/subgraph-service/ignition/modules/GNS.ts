import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import L2GNSArtifact from '@graphprotocol/contracts/artifacts/contracts/l2/discovery/L2GNS.sol/L2GNS.json'
import SubgraphNFTArtifact from '@graphprotocol/contracts/artifacts/contracts/discovery/SubgraphNFT.sol/SubgraphNFT.json'

// Note that this module is a no-op, we only run it to get gns addresses into the address book.
// GNS deployment should be managed by ignition scripts in subgraph-service package however
// due to tight coupling with Controller contract it's easier to do it on the horizon package.

export default buildModule('L2GNS', (m) => {
  const gnsProxyAddress = m.getParameter('gnsProxyAddress')
  const gnsImplementationAddress = m.getParameter('gnsImplementationAddress')
  const subgraphNFTAddress = m.getParameter('subgraphNFTAddress')

  const SubgraphNFT = m.contractAt('SubgraphNFTAddressBook', SubgraphNFTArtifact, subgraphNFTAddress)
  const L2GNS = m.contractAt('L2GNSAddressBook', L2GNSArtifact, gnsProxyAddress)
  const L2GNSImplementation = m.contractAt('L2GNSImplementationAddressBook', L2GNSArtifact, gnsImplementationAddress)

  return { L2GNS, L2GNSImplementation, SubgraphNFT }
})
