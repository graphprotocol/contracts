import { buildModule, IgnitionModuleBuilder } from '@nomicfoundation/ignition-core'
import { deployWithGraphProxy, upgradeWithGraphProxy } from '../proxy/GraphProxy'

import ControllerModule from '../periphery/Controller'

import RewardsManagerArtifact from '@graphprotocol/contracts/build/contracts/contracts/rewards/RewardsManager.sol/RewardsManager.json'
import GraphProxyArtifact from '@graphprotocol/contracts/build/contracts/contracts/upgrades/GraphProxy.sol/GraphProxy.json'

export default buildModule('RewardsManager', (m) => {
  const isMigrate = m.getParameter('isMigrate')

  if (isMigrate) {
    return upgradeRewardsManager(m)
  } else {
    return deployRewardsManager(m)
  }
})

function upgradeRewardsManager(m: IgnitionModuleBuilder) {
  const governor = m.getAccount(1)

  const subgraphServiceAddress = m.getParameter('subgraphServiceAddress')
  const rewardsManagerProxyAddress = m.getParameter('rewardsManagerProxyAddress')
  const GraphProxy = m.contractAt('GraphProxy', GraphProxyArtifact, rewardsManagerProxyAddress)

  const { instance: RewardsManager, implementation: RewardsManagerImplementation } = upgradeWithGraphProxy(m, {
    name: 'RewardsManager',
    artifact: RewardsManagerArtifact,
    proxyContract: GraphProxy,
  }, { from: governor })
  m.call(RewardsManager, 'setSubgraphService', [subgraphServiceAddress], { from: governor })

  return { instance: RewardsManager, implementation: RewardsManagerImplementation }
}

function deployRewardsManager(m: IgnitionModuleBuilder) {
  const { Controller } = m.useModule(ControllerModule)
  const { instance: RewardsManager, implementation: RewardsManagerImplementation } = deployWithGraphProxy(m, {
    name: 'RewardsManager',
    artifact: RewardsManagerArtifact,
    args: [Controller],
  })

  const issuancePerBlock = m.getParameter('issuancePerBlock')
  const subgraphAvailabilityOracle = m.getParameter('subgraphAvailabilityOracle')
  const subgraphServiceAddress = m.getParameter('subgraphServiceAddress')

  m.call(RewardsManager, 'setSubgraphAvailabilityOracle', [subgraphAvailabilityOracle])
  m.call(RewardsManager, 'setIssuancePerBlock', [issuancePerBlock])
  m.call(RewardsManager, 'setSubgraphService', [subgraphServiceAddress])

  return { instance: RewardsManager, implementation: RewardsManagerImplementation }
}
