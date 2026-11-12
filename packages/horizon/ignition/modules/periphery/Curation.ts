import GraphCurationTokenArtifact from '@graphprotocol/graph-token/artifacts/contracts/curation/GraphCurationToken.sol/GraphCurationToken.json'
import { type Artifact, buildModule } from '@nomicfoundation/ignition-core'

import { deployWithGraphProxy } from '../proxy/GraphProxy'
import ControllerModule from './Controller'
import GraphProxyAdminModule from './GraphProxyAdmin'

// Curation deployment should be managed by ignition scripts in subgraph-service package however
// due to tight coupling with Controller it's easier to do it on the horizon package.
// The L2Curation artifact comes from subgraph-service, which horizon can't depend on.

export function buildCurationModule(artifact: Artifact) {
  return buildModule('L2Curation', (m) => {
    const { Controller } = m.useModule(ControllerModule)
    const { GraphProxyAdmin } = m.useModule(GraphProxyAdminModule)

    const curationTaxPercentage = m.getParameter('curationTaxPercentage')
    const minimumCurationDeposit = m.getParameter('minimumCurationDeposit')
    const subgraphServiceAddress = m.getParameter('subgraphServiceAddress')

    const GraphCurationToken = m.contract('GraphCurationToken', GraphCurationTokenArtifact, [])

    const { proxy: L2Curation, implementation: L2CurationImplementation } = deployWithGraphProxy(m, GraphProxyAdmin, {
      name: 'L2Curation',
      artifact,
      initArgs: [Controller, GraphCurationToken, curationTaxPercentage, minimumCurationDeposit],
    })
    m.call(L2Curation, 'setSubgraphService', [subgraphServiceAddress])

    return { L2Curation, L2CurationImplementation }
  })
}
