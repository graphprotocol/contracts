import CurationArtifact from '@graphprotocol/contracts/artifacts/contracts/l2/curation/L2Curation.sol/L2Curation.json'
import { buildModule } from '@nomicfoundation/ignition-core'

// Note that this module is a no-op, we only run it to get curation addresses into the address book.
// Curation deployment should be managed by ignition scripts in subgraph-service package however
// due to tight coupling with Controller contract it's easier to do it on the horizon package.

export default buildModule('L2Curation', (m) => {
  const curationProxyAddress = m.getParameter('curationProxyAddress')
  const curationImplementationAddress = m.getParameter('curationImplementationAddress')

  const L2Curation = m.contractAt('L2CurationAddressBook', CurationArtifact, curationProxyAddress)
  const L2CurationImplementation = m.contractAt(
    'L2CurationImplementationAddressBook',
    CurationArtifact,
    curationImplementationAddress,
  )

  return { L2Curation, L2CurationImplementation }
})
