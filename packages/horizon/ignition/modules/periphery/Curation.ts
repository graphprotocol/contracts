import { buildModule, IgnitionModuleBuilder } from '@nomicfoundation/ignition-core'
import { deployWithGraphProxy, upgradeWithGraphProxy } from '../proxy/GraphProxy'

import ControllerModule from './Controller'

import CurationArtifact from '@graphprotocol/contracts/build/contracts/contracts/l2/curation/L2Curation.sol/L2Curation.json'
import GraphCurationTokenArtifact from '@graphprotocol/contracts/build/contracts/contracts/curation/GraphCurationToken.sol/GraphCurationToken.json'
import GraphProxyArtifact from '@graphprotocol/contracts/build/contracts/contracts/upgrades/GraphProxy.sol/GraphProxy.json'

export default buildModule('Curation', (m) => {
  const isMigrate = m.getParameter('isMigrate')

  if (isMigrate) {
    return upgradeCuration(m)
  } else {
    return deployCuration(m)
  }
})

function upgradeCuration(m: IgnitionModuleBuilder) {
  const governor = m.getAccount(1)

  const graphCurationProxyAddress = m.getParameter('graphCurationProxyAddress')
  const subgraphServiceAddress = m.getParameter('subgraphServiceAddress')

  const GraphProxy = m.contractAt('GraphProxy', GraphProxyArtifact, graphCurationProxyAddress)
  const { instance: Curation, implementation: CurationImplementation } = upgradeWithGraphProxy(m, {
    name: 'Curation',
    artifact: CurationArtifact,
    proxyContract: GraphProxy,
  }, { from: governor })
  m.call(Curation, 'setSubgraphService', [subgraphServiceAddress], { from: governor })

  return { instance: Curation, implementation: CurationImplementation }
}

function deployCuration(m: IgnitionModuleBuilder) {
  const curationTaxPercentage = m.getParameter('curationTaxPercentage')
  const minimumCurationDeposit = m.getParameter('minimumCurationDeposit')
  const subgraphServiceAddress = m.getParameter('subgraphServiceAddress')

  const { Controller } = m.useModule(ControllerModule)
  const GraphCurationToken = m.contract('GraphCurationToken', GraphCurationTokenArtifact, [])

  const { instance: Curation, implementation: CurationImplementation } = deployWithGraphProxy(m, {
    name: 'Curation',
    artifact: CurationArtifact,
    args: [Controller, GraphCurationToken, curationTaxPercentage, minimumCurationDeposit],
  })
  m.call(Curation, 'setSubgraphService', [subgraphServiceAddress])

  return { instance: Curation, implementation: CurationImplementation }
}
