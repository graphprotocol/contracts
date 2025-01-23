import { buildModule, IgnitionModuleBuilder } from '@nomicfoundation/ignition-core'
import { deployWithGraphProxy, upgradeGraphProxy } from '../proxy/GraphProxy'
import { deployImplementation } from '../proxy/implementation'

import ControllerModule from './Controller'
import GraphProxyAdminModule from './GraphProxyAdmin'

import RewardsManagerArtifact from '@graphprotocol/contracts/build/contracts/contracts/rewards/RewardsManager.sol/RewardsManager.json'

export default buildModule('RewardsManager', (m) => {
  const { Controller } = m.useModule(ControllerModule)
  const { GraphProxyAdmin } = m.useModule(GraphProxyAdminModule)

  const issuancePerBlock = m.getParameter('issuancePerBlock')
  const subgraphAvailabilityOracle = m.getParameter('subgraphAvailabilityOracle')
  const subgraphServiceAddress = m.getParameter('subgraphServiceAddress')

  const RewardsManager = deployWithGraphProxy(m, GraphProxyAdmin, {
    name: 'RewardsManager',
    artifact: RewardsManagerArtifact,
    initArgs: [Controller],
  })
  m.call(RewardsManager, 'setSubgraphAvailabilityOracle', [subgraphAvailabilityOracle])
  m.call(RewardsManager, 'setIssuancePerBlock', [issuancePerBlock])
  m.call(RewardsManager, 'setSubgraphService', [subgraphServiceAddress])

  return { RewardsManager }
})

// RewardsManager contract is owned by the governor
export const MigrateRewardsManagerModule = buildModule('RewardsManager', (m: IgnitionModuleBuilder) => {
  const governor = m.getAccount(1)
  const subgraphServiceAddress = m.getParameter('subgraphServiceAddress')
  const rewardsManagerProxyAddress = m.getParameter('rewardsManagerProxyAddress')
  const graphProxyAdminAddress = m.getParameter('graphProxyAdminAddress')

  const implementationMetadata = {
    name: 'RewardsManager',
    artifact: RewardsManagerArtifact,
  }
  const implementation = deployImplementation(m, implementationMetadata)

  const RewardsManager = upgradeGraphProxy(m, graphProxyAdminAddress, rewardsManagerProxyAddress, implementation, implementationMetadata, { from: governor })
  m.call(RewardsManager, 'setSubgraphService', [subgraphServiceAddress], { from: governor })

  return { RewardsManager }
})
