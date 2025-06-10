import { buildModule, IgnitionModuleBuilder } from '@nomicfoundation/ignition-core'
import { deployWithGraphProxy, upgradeGraphProxy } from '../proxy/GraphProxy'
import { deployImplementation } from '../proxy/implementation'

import ControllerModule from './Controller'
import GraphProxyAdminModule from './GraphProxyAdmin'

import CurationArtifact from '@graphprotocol/contracts/artifacts/contracts/l2/curation/L2Curation.sol/L2Curation.json'
import GraphCurationTokenArtifact from '@graphprotocol/contracts/artifacts/contracts/curation/GraphCurationToken.sol/GraphCurationToken.json'
import GraphProxyAdminArtifact from '@graphprotocol/contracts/artifacts/contracts/upgrades/GraphProxyAdmin.sol/GraphProxyAdmin.json'
import GraphProxyArtifact from '@graphprotocol/contracts/artifacts/contracts/upgrades/GraphProxy.sol/GraphProxy.json'

// Curation deployment should be managed by ignition scripts in subgraph-service package however
// due to tight coupling with Controller it's easier to do it on the horizon package.

export default buildModule('L2Curation', (m) => {
  const { Controller } = m.useModule(ControllerModule)
  const { GraphProxyAdmin } = m.useModule(GraphProxyAdminModule)

  const curationTaxPercentage = m.getParameter('curationTaxPercentage')
  const minimumCurationDeposit = m.getParameter('minimumCurationDeposit')
  const subgraphServiceAddress = m.getParameter('subgraphServiceAddress')

  const GraphCurationToken = m.contract('GraphCurationToken', GraphCurationTokenArtifact, [])

  const { proxy: L2Curation, implementation: L2CurationImplementation } = deployWithGraphProxy(m, GraphProxyAdmin, {
    name: 'L2Curation',
    artifact: CurationArtifact,
    initArgs: [Controller, GraphCurationToken, curationTaxPercentage, minimumCurationDeposit],
  })
  m.call(L2Curation, 'setSubgraphService', [subgraphServiceAddress])

  return { L2Curation, L2CurationImplementation }
})

export const MigrateCurationDeployerModule = buildModule('L2CurationDeployer', (m: IgnitionModuleBuilder) => {
  const curationAddress = m.getParameter('curationAddress')

  const L2CurationProxy = m.contractAt('L2CurationProxy', GraphProxyArtifact, curationAddress)

  const implementationMetadata = {
    name: 'L2Curation',
    artifact: CurationArtifact,
  }
  const L2CurationImplementation = deployImplementation(m, implementationMetadata)

  return { L2CurationProxy, L2CurationImplementation }
})

export const MigrateCurationGovernorModule = buildModule('L2CurationGovernor', (m: IgnitionModuleBuilder) => {
  const curationAddress = m.getParameter('curationAddress')
  const curationImplementationAddress = m.getParameter('curationImplementationAddress')
  const subgraphServiceAddress = m.getParameter('subgraphServiceAddress')
  const graphProxyAdminAddress = m.getParameter('graphProxyAdminAddress')

  const GraphProxyAdmin = m.contractAt('GraphProxyAdmin', GraphProxyAdminArtifact, graphProxyAdminAddress)
  const L2CurationProxy = m.contractAt('L2CurationProxy', GraphProxyArtifact, curationAddress)
  const L2CurationImplementation = m.contractAt('L2CurationImplementation', CurationArtifact, curationImplementationAddress)

  const implementationMetadata = {
    name: 'L2Curation',
    artifact: CurationArtifact,
  }

  const L2Curation = upgradeGraphProxy(m, GraphProxyAdmin, L2CurationProxy, L2CurationImplementation, implementationMetadata)
  m.call(L2Curation, 'setSubgraphService', [subgraphServiceAddress])

  return { L2Curation, L2CurationImplementation }
})
