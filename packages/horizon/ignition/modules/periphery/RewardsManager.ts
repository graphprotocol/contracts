import RewardsManagerArtifact from '@graphprotocol/issuance/artifacts/contracts/rewards/RewardsManager.sol/RewardsManager.json'
import { buildModule } from '@nomicfoundation/ignition-core'

import { deployWithGraphProxy } from '../proxy/GraphProxy'
import ControllerModule from './Controller'
import GraphProxyAdminModule from './GraphProxyAdmin'

export default buildModule('RewardsManager', (m) => {
  const { Controller } = m.useModule(ControllerModule)
  const { GraphProxyAdmin } = m.useModule(GraphProxyAdminModule)

  const issuancePerBlock = m.getParameter('issuancePerBlock')
  const subgraphAvailabilityOracle = m.getParameter('subgraphAvailabilityOracle')
  const subgraphServiceAddress = m.getParameter('subgraphServiceAddress')

  const { proxy: RewardsManager, implementation: RewardsManagerImplementation } = deployWithGraphProxy(
    m,
    GraphProxyAdmin,
    {
      name: 'RewardsManager',
      artifact: RewardsManagerArtifact,
      initArgs: [Controller],
    },
  )
  m.call(RewardsManager, 'setSubgraphAvailabilityOracle', [subgraphAvailabilityOracle])
  m.call(RewardsManager, 'setIssuancePerBlock', [issuancePerBlock])
  m.call(RewardsManager, 'setSubgraphService', [subgraphServiceAddress])

  return { RewardsManager, RewardsManagerImplementation }
})
