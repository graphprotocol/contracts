import { buildModule, IgnitionModuleBuilder } from '@nomicfoundation/ignition-core'
import { deployWithGraphProxy, upgradeGraphProxy } from '../proxy/GraphProxy'
import { deployImplementation } from '../proxy/implementation'

import ControllerModule from './Controller'
import GraphProxyAdminModule from './GraphProxyAdmin'

import GraphProxyAdminArtifact from '@graphprotocol/contracts/build/contracts/contracts/upgrades/GraphProxyAdmin.sol/GraphProxyAdmin.json'
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
  const rewardsManagerAddress = m.getParameter('rewardsManagerAddress')
  const rewardsManagerImplementationAddress = m.getParameter('rewardsManagerImplementationAddress')
  const graphProxyAdminAddress = m.getParameter('graphProxyAdminAddress')

  const GraphProxyAdmin = m.contractAt('GraphProxyAdmin', GraphProxyAdminArtifact, graphProxyAdminAddress)
  const RewardsManagerProxy = m.contractAt('RewardsManagerProxy', GraphProxyArtifact, rewardsManagerAddress)
  const RewardsManagerImplementation = m.contractAt('RewardsManagerImplementation', RewardsManagerArtifact, rewardsManagerImplementationAddress)

  const subgraphServiceAddress = m.getParameter('subgraphServiceAddress')

  const implementationMetadata = {
    name: 'RewardsManager',
    artifact: RewardsManagerArtifact,
  }

  const RewardsManager = upgradeGraphProxy(m, GraphProxyAdmin, RewardsManagerProxy, RewardsManagerImplementation, implementationMetadata)
  m.call(RewardsManager, 'setSubgraphService', [subgraphServiceAddress])

  return { RewardsManager }
})
