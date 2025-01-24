import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import { deployImplementation } from '../proxy/implementation'
import { upgradeGraphProxyNoLoad } from '../proxy/GraphProxy'

import GraphPeripheryModule, { MigratePeripheryModule } from '../periphery/periphery'
import HorizonProxiesModule, { MigrateHorizonProxiesModule } from './HorizonProxies'

import ControllerArtifact from '@graphprotocol/contracts/build/contracts/contracts/governance/Controller.sol/Controller.json'
import ExponentialRebatesArtifact from '../../../build/contracts/contracts/staking/libraries/ExponentialRebates.sol/ExponentialRebates.json'
import GraphProxyAdminArtifact from '@graphprotocol/contracts/build/contracts/contracts/upgrades/GraphProxyAdmin.sol/GraphProxyAdmin.json'
import GraphProxyArtifact from '@graphprotocol/contracts/build/contracts/contracts/upgrades/GraphProxy.sol/GraphProxy.json'
import HorizonStakingArtifact from '../../../build/contracts/contracts/staking/HorizonStaking.sol/HorizonStaking.json'
import HorizonStakingExtensionArtifact from '../../../build/contracts/contracts/staking/HorizonStakingExtension.sol/HorizonStakingExtension.json'

export default buildModule('HorizonStaking', (m) => {
  const { Controller, GraphProxyAdmin } = m.useModule(GraphPeripheryModule)
  const { HorizonStakingProxy } = m.useModule(HorizonProxiesModule)

  const subgraphServiceAddress = m.getParameter('subgraphServiceAddress')
  const maxThawingPeriod = m.getParameter('maxThawingPeriod')

  // Deploy HorizonStakingExtension - requires periphery and proxies to be registered in the controller
  const ExponentialRebates = m.library('ExponentialRebates', ExponentialRebatesArtifact)
  const HorizonStakingExtension = m.contract('HorizonStakingExtension',
    HorizonStakingExtensionArtifact,
    [Controller, subgraphServiceAddress], {
      libraries: {
        ExponentialRebates: ExponentialRebates,
      },
      after: [GraphPeripheryModule, HorizonProxiesModule],
    })

  // Deploy HorizonStaking implementation
  const HorizonStakingImplementation = deployImplementation(m, {
    name: 'HorizonStaking',
    artifact: HorizonStakingArtifact,
    constructorArgs: [Controller, HorizonStakingExtension, subgraphServiceAddress],
  })

  // Upgrade proxy to implementation contract
  const HorizonStaking = upgradeGraphProxyNoLoad(m, GraphProxyAdmin, HorizonStakingProxy, HorizonStakingImplementation, {
    name: 'HorizonStaking',
    artifact: HorizonStakingArtifact,
  })
  m.call(HorizonStaking, 'setMaxThawingPeriod', [maxThawingPeriod])

  return { HorizonStaking }
})

// HorizonStaking contract is owned by the governor
export const MigrateHorizonStakingModule = buildModule('HorizonStaking', (m) => {
  const governor = m.getAccount(1)
  const maxThawingPeriod = m.getParameter('maxThawingPeriod')
  const subgraphServiceAddress = m.getParameter('subgraphServiceAddress')
  const horizonStakingProxyAddress = m.getParameter('horizonStakingProxyAddress')
  const controllerAddress = m.getParameter('controllerAddress')
  const graphProxyAdminAddress = m.getParameter('graphProxyAdminAddress')

  const Controller = m.contractAt('Controller', ControllerArtifact, controllerAddress)
  const GraphProxyAdmin = m.contractAt('GraphProxyAdmin', GraphProxyAdminArtifact, graphProxyAdminAddress)
  const HorizonStakingProxy = m.contractAt('HorizonStakingProxy', GraphProxyArtifact, horizonStakingProxyAddress)

  // Deploy HorizonStakingExtension - requires periphery and proxies to be registered in the controller
  const ExponentialRebates = m.library('ExponentialRebates', ExponentialRebatesArtifact)
  const HorizonStakingExtension = m.contract('HorizonStakingExtension',
    HorizonStakingExtensionArtifact,
    [Controller, subgraphServiceAddress], {
      libraries: {
        ExponentialRebates: ExponentialRebates,
      },
      after: [MigrateHorizonProxiesModule, MigratePeripheryModule],
    })

  // Deploy HorizonStaking implementation
  const HorizonStakingImplementation = deployImplementation(m, {
    name: 'HorizonStaking',
    artifact: HorizonStakingArtifact,
    constructorArgs: [Controller, HorizonStakingExtension, subgraphServiceAddress],
  })

  // Upgrade proxy to implementation contract
  const HorizonStaking = upgradeGraphProxyNoLoad(m, GraphProxyAdmin, HorizonStakingProxy, HorizonStakingImplementation, {
    name: 'HorizonStaking',
    artifact: HorizonStakingArtifact,
  }, { from: governor })
  m.call(HorizonStaking, 'setMaxThawingPeriod', [maxThawingPeriod], { from: governor })

  return { HorizonStaking }
})
