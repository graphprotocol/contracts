import { expect } from 'chai'

import { getFullyQualifiedContractName } from '../tasks/verify-contract.js'

describe('getFullyQualifiedContractName', function () {
  it('uses the basename after .sol: for subgraph-service contracts in subdirectories', function () {
    expect(getFullyQualifiedContractName({ type: 'subgraph-service', name: 'l2/curation/L2Curation' })).to.equal(
      'contracts/l2/curation/L2Curation.sol:L2Curation',
    )
  })
})
