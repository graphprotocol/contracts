import { buildModule } from '@nomicfoundation/ignition-core'

import CurationArtifact from '@graphprotocol/contracts/build/contracts/contracts/l2/curation/L2Curation.sol/L2Curation.json'

// Note that this module is a no-op, we only run it to get curation addresses into the address book.
// Curation deployment should be managed by ignition scripts in subgraph-service package however
// due to tight coupling with HorizonStakingExtension contract it's easier to do it on the horizon package.
// Once the transition period is over we can migrate it.
export default buildModule('L2Curation', (m) => {
  const curationAddress = m.getParameter('curationAddress')
  const curationImplementationAddress = m.getParameter('curationImplementationAddress')

  const L2Curation = m.contractAt('L2Curation', CurationArtifact, curationAddress)
  const L2CurationImplementation = m.contractAt('L2CurationImplementation', CurationArtifact, curationImplementationAddress)

  return { L2Curation, L2CurationImplementation }
})
