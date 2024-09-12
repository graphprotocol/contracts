import { buildModule } from '@nomicfoundation/ignition-core'

import { deployWithGraphProxy } from '../lib/proxy'

import ControllerModule from '../periphery/Controller'
import RewardsManagerArtifact from '@graphprotocol/contracts/build/contracts/contracts/rewards/RewardsManager.sol/RewardsManager.json'

export default buildModule('RewardsManager', (m) => {
  const { Controller } = m.useModule(ControllerModule)

  const issuancePerBlock = m.getParameter('issuancePerBlock')
  const subgraphAvailabilityOracle = m.getParameter('subgraphAvailabilityOracle')
  const subgraphServiceAddress = m.getParameter('subgraphServiceAddress')

  const { instance: RewardsManager } = deployWithGraphProxy(m, {
    name: 'RewardsManager',
    artifact: RewardsManagerArtifact,
    args: [Controller],
  })

  m.call(RewardsManager, 'setSubgraphAvailabilityOracle', [subgraphAvailabilityOracle])
  m.call(RewardsManager, 'setIssuancePerBlock', [issuancePerBlock])
  m.call(RewardsManager, 'setSubgraphService', [subgraphServiceAddress])

  return { RewardsManager }
})
