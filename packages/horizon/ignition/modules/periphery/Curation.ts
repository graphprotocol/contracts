import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import { deployWithGraphProxy } from '../lib/proxy'

import ControllerModule from './Controller'
import CurationArtifact from '@graphprotocol/contracts/build/contracts/contracts/l2/curation/L2Curation.sol/L2Curation.json'
import GraphCurationTokenArtifact from '@graphprotocol/contracts/build/contracts/contracts/curation/GraphCurationToken.sol/GraphCurationToken.json'

export default buildModule('Curation', (m) => {
  const { Controller } = m.useModule(ControllerModule)

  const curationTaxPercentage = m.getParameter('curationTaxPercentage')
  const minimumCurationDeposit = m.getParameter('minimumCurationDeposit')

  const GraphCurationToken = m.contract('GraphCurationToken', GraphCurationTokenArtifact, [])

  const { instance: Curation } = deployWithGraphProxy(m, {
    name: 'Curation',
    artifact: CurationArtifact,
    args: [Controller, GraphCurationToken, curationTaxPercentage, minimumCurationDeposit],
  })

  return { Curation }
})
