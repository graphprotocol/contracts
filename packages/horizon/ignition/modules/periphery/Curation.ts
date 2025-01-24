import { buildModule, IgnitionModuleBuilder } from '@nomicfoundation/ignition-core'
import { deployWithGraphProxy, upgradeGraphProxy } from '../proxy/GraphProxy'
import { deployImplementation } from '../proxy/implementation'

import GraphProxyAdminModule, { MigrateGraphProxyAdminModule } from './GraphProxyAdmin'
import ControllerModule from './Controller'

import CurationArtifact from '@graphprotocol/contracts/build/contracts/contracts/l2/curation/L2Curation.sol/L2Curation.json'
import GraphCurationTokenArtifact from '@graphprotocol/contracts/build/contracts/contracts/curation/GraphCurationToken.sol/GraphCurationToken.json'

export default buildModule('L2Curation', (m) => {
  const { Controller } = m.useModule(ControllerModule)
  const { GraphProxyAdmin } = m.useModule(GraphProxyAdminModule)

  const curationTaxPercentage = m.getParameter('curationTaxPercentage')
  const minimumCurationDeposit = m.getParameter('minimumCurationDeposit')
  const subgraphServiceAddress = m.getParameter('subgraphServiceAddress')

  const GraphCurationToken = m.contract('GraphCurationToken', GraphCurationTokenArtifact, [])

  const L2Curation = deployWithGraphProxy(m, GraphProxyAdmin, {
    name: 'L2Curation',
    artifact: CurationArtifact,
    initArgs: [Controller, GraphCurationToken, curationTaxPercentage, minimumCurationDeposit],
  })
  m.call(L2Curation, 'setSubgraphService', [subgraphServiceAddress])

  return { L2Curation }
})

// Curation contract is owned by the governor
export const MigrateCurationModule = buildModule('L2Curation', (m: IgnitionModuleBuilder) => {
  const { GraphProxyAdmin } = m.useModule(MigrateGraphProxyAdminModule)

  const governor = m.getAccount(1)
  const curationAddress = m.getParameter('curationAddress')
  const subgraphServiceAddress = m.getParameter('subgraphServiceAddress')

  const implementationMetadata = {
    name: 'L2Curation',
    artifact: CurationArtifact,
  }
  const implementation = deployImplementation(m, implementationMetadata)

  const L2Curation = upgradeGraphProxy(m, GraphProxyAdmin, curationAddress, implementation, implementationMetadata, { from: governor })
  m.call(L2Curation, 'setSubgraphService', [subgraphServiceAddress], { from: governor })

  return { L2Curation }
})
