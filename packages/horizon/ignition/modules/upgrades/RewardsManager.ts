import RewardsManagerArtifact from '@graphprotocol/contracts/artifacts/contracts/rewards/RewardsManager.sol/RewardsManager.json'
import GraphProxyArtifact from '@graphprotocol/contracts/artifacts/contracts/upgrades/GraphProxy.sol/GraphProxy.json'
import GraphProxyAdminArtifact from '@graphprotocol/contracts/artifacts/contracts/upgrades/GraphProxyAdmin.sol/GraphProxyAdmin.json'
import { buildModule } from '@nomicfoundation/ignition-core'

import { upgradeGraphProxy } from '../proxy/GraphProxy'
import { deployImplementation } from '../proxy/implementation'

export const UpgradeRewardsManagerDeployerModule = buildModule('UpgradeRewardsManagerDeployer', (m) => {
  const rewardsManagerAddress = m.getParameter('rewardsManagerAddress')
  const RewardsManagerProxy = m.contractAt('RewardsManagerProxy', GraphProxyArtifact, rewardsManagerAddress)

  deployImplementation(
    m,
    {
      name: 'RewardsManager',
      artifact: RewardsManagerArtifact,
    },
    { id: 'RewardsManagerV2' },
  )

  const RewardsManagerV3 = deployImplementation(
    m,
    {
      name: 'RewardsManager',
      artifact: RewardsManagerArtifact,
    },
    { id: 'RewardsManagerV3' },
  )

  return { RewardsManagerProxy, Implementation_RewardsManager: RewardsManagerV3 }
})

export const UpgradeRewardsManagerGovernorModule = buildModule('UpgradeRewardsManagerGovernor', (m) => {
  const rewardsManagerAddress = m.getParameter('rewardsManagerAddress')
  const graphProxyAdminAddress = m.getParameter('graphProxyAdminAddress')

  const RewardsManagerProxy = m.contractAt('RewardsManagerProxy', GraphProxyArtifact, rewardsManagerAddress)
  const GraphProxyAdmin = m.contractAt('GraphProxyAdmin', GraphProxyAdminArtifact, graphProxyAdminAddress)

  const rewardsManagerV2Address = m.getParameter('rewardsManagerV2Address')
  const RewardsManagerImplV2 = m.contractAt('RewardsManagerImplV2', RewardsManagerArtifact, rewardsManagerV2Address)
  upgradeGraphProxy(
    m,
    GraphProxyAdmin,
    RewardsManagerProxy,
    RewardsManagerImplV2,
    { name: 'RewardsManager', artifact: RewardsManagerArtifact },
    { id: 'upgradeRewardsManagerV2' },
  )

  const rewardsManagerV3Address = m.getParameter('rewardsManagerV3Address')
  const RewardsManagerImplV3 = m.contractAt('RewardsManagerImplV3', RewardsManagerArtifact, rewardsManagerV3Address)
  const RewardsManagerV3 = upgradeGraphProxy(
    m,
    GraphProxyAdmin,
    RewardsManagerProxy,
    RewardsManagerImplV3,
    { name: 'RewardsManager', artifact: RewardsManagerArtifact },
    { id: 'upgradeRewardsManagerV3' },
  )

  return { RewardsManagerV3 }
})
