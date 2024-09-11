import { buildModule } from '@nomicfoundation/ignition-core'

import { deployWithGraphProxy } from '../lib/proxy'

import ControllerModule from '../periphery/Controller'
import RewardsManagerArtifact from '@graphprotocol/contracts/build/contracts/contracts/rewards/RewardsManager.sol/RewardsManager.json'

// TODO: syncAllContracts post deploy
export default buildModule('RewardsManager', (m) => {
  const { Controller } = m.useModule(ControllerModule)

  const issuancePerBlock = m.getParameter('issuancePerBlock')
  const subgraphAvailabilityOracle = m.getParameter('subgraphAvailabilityOracle')

  const { instance: RewardsManager } = deployWithGraphProxy(m, {
    name: 'RewardsManager',
    artifact: RewardsManagerArtifact,
    args: [Controller],
  })

  m.call(RewardsManager, 'setSubgraphAvailabilityOracle', [subgraphAvailabilityOracle])
  m.call(RewardsManager, 'setIssuancePerBlock', [issuancePerBlock])
  // TODO: setSubgraphService
  // m.call(RewardsManager, 'setSubgraphService', [])

  return { RewardsManager }
})
