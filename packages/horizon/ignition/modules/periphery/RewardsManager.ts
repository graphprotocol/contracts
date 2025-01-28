import { buildModule, IgnitionModuleBuilder } from '@nomicfoundation/ignition-core'
import { deployWithGraphProxy, upgradeGraphProxy } from '../proxy/GraphProxy'
import { deployImplementation } from '../proxy/implementation'

import GraphProxyAdminModule, { MigrateGraphProxyAdminModule } from './GraphProxyAdmin'
import ControllerModule from './Controller'

import GraphProxyArtifact from '@graphprotocol/contracts/build/contracts/contracts/upgrades/GraphProxy.sol/GraphProxy.json'
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

export const MigrateRewardsManagerDeployerModule = buildModule('RewardsManagerDeployer', (m: IgnitionModuleBuilder) => {
  const rewardsManagerAddress = m.getParameter('rewardsManagerAddress')

  const RewardsManagerProxy = m.contractAt('RewardsManagerProxy', GraphProxyArtifact, rewardsManagerAddress)

  const implementationMetadata = {
    name: 'RewardsManager',
    artifact: RewardsManagerArtifact,
  }
  const RewardsManagerImplementation = deployImplementation(m, implementationMetadata)

  return { RewardsManagerProxy, RewardsManagerImplementation }
})

export const MigrateRewardsManagerGovernorModule = buildModule('RewardsManagerGovernor', (m: IgnitionModuleBuilder) => {
  const { GraphProxyAdmin } = m.useModule(MigrateGraphProxyAdminModule)
  const { RewardsManagerProxy, RewardsManagerImplementation } = m.useModule(MigrateRewardsManagerDeployerModule)

  const governor = m.getAccount(1)
  const subgraphServiceAddress = m.getParameter('subgraphServiceAddress')

  const implementationMetadata = {
    name: 'RewardsManager',
    artifact: RewardsManagerArtifact,
  }

  const RewardsManager = upgradeGraphProxy(m, GraphProxyAdmin, RewardsManagerProxy, RewardsManagerImplementation, implementationMetadata, { from: governor })
  m.call(RewardsManager, 'setSubgraphService', [subgraphServiceAddress], { from: governor })

  return { RewardsManager }
})
