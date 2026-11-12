import SubgraphNFTArtifact from '@graphprotocol/graph-token/artifacts/contracts/discovery/SubgraphNFT.sol/SubgraphNFT.json'
import SubgraphNFTDescriptorArtifact from '@graphprotocol/graph-token/artifacts/contracts/discovery/SubgraphNFTDescriptor.sol/SubgraphNFTDescriptor.json'
import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import type { Artifact } from '@nomicfoundation/ignition-core'

import { deployWithGraphProxy } from '../proxy/GraphProxy'
import ControllerModule from './Controller'
import type { buildCurationModule } from './Curation'
import GraphProxyAdminModule from './GraphProxyAdmin'
import GraphTokenModule from './GraphToken'

// GNS deployment should be managed by ignition scripts in subgraph-service package however
// due to tight coupling with Controller it's easier to do it on the horizon package.
// The L2GNS artifact comes from subgraph-service, which horizon can't depend on.

export function buildGNSModule(artifact: Artifact, CurationModule: ReturnType<typeof buildCurationModule>) {
  return buildModule('L2GNS', (m) => {
    const { Controller } = m.useModule(ControllerModule)
    const { GraphProxyAdmin } = m.useModule(GraphProxyAdminModule)
    const { L2GraphToken } = m.useModule(GraphTokenModule)
    const { L2Curation } = m.useModule(CurationModule)

    const deployer = m.getAccount(0)
    const governor = m.getParameter('governor')

    const SubgraphNFTDescriptor = m.contract('SubgraphNFTDescriptor', SubgraphNFTDescriptorArtifact)
    const SubgraphNFT = m.contract('SubgraphNFT', SubgraphNFTArtifact, [deployer])

    m.call(SubgraphNFT, 'setTokenDescriptor', [SubgraphNFTDescriptor])

    const { proxy: L2GNS, implementation: L2GNSImplementation } = deployWithGraphProxy(m, GraphProxyAdmin, {
      name: 'L2GNS',
      artifact,
      initArgs: [Controller, SubgraphNFT],
    })
    m.call(L2GNS, 'approveAll', [], { after: [L2GraphToken, L2Curation] })

    const setMinterCall = m.call(SubgraphNFT, 'setMinter', [L2GNS])
    m.call(SubgraphNFT, 'transferOwnership', [governor], { after: [setMinterCall] })

    return { L2GNS, L2GNSImplementation, SubgraphNFT }
  })
}
