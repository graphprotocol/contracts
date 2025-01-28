import { acceptUpgradeGraphProxy, deployWithGraphProxy } from '../proxy/GraphProxy'
import { buildModule, IgnitionModuleBuilder } from '@nomicfoundation/ignition-core'
import { deployImplementation } from '../proxy/implementation'

import ControllerModule from './Controller'
import GraphProxyAdminModule from './GraphProxyAdmin'

import CurationArtifact from '@graphprotocol/contracts/build/contracts/contracts/l2/curation/L2Curation.sol/L2Curation.json'
import GraphCurationTokenArtifact from '@graphprotocol/contracts/build/contracts/contracts/curation/GraphCurationToken.sol/GraphCurationToken.json'
import GraphProxyAdminArtifact from '@graphprotocol/contracts/build/contracts/contracts/upgrades/GraphProxyAdmin.sol/GraphProxyAdmin.json'
import GraphProxyArtifact from '@graphprotocol/contracts/build/contracts/contracts/upgrades/GraphProxy.sol/GraphProxy.json'

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

  const L2Curation = acceptUpgradeGraphProxy(m, GraphProxyAdmin, L2CurationProxy, L2CurationImplementation, implementationMetadata)
  m.call(L2Curation, 'setSubgraphService', [subgraphServiceAddress])

  return { L2Curation }
})
