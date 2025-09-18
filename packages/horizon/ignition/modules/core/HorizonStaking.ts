import GraphProxyArtifact from '@graphprotocol/contracts/artifacts/contracts/upgrades/GraphProxy.sol/GraphProxy.json'
import GraphProxyAdminArtifact from '@graphprotocol/contracts/artifacts/contracts/upgrades/GraphProxyAdmin.sol/GraphProxyAdmin.json'
import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import HorizonStakingArtifact from '../../../build/contracts/contracts/staking/HorizonStaking.sol/HorizonStaking.json'
import HorizonStakingExtensionArtifact from '../../../build/contracts/contracts/staking/HorizonStakingExtension.sol/HorizonStakingExtension.json'
import ExponentialRebatesArtifact from '../../../build/contracts/contracts/staking/libraries/ExponentialRebates.sol/ExponentialRebates.json'
import GraphPeripheryModule, { MigratePeripheryModule } from '../periphery/periphery'
import { upgradeGraphProxy } from '../proxy/GraphProxy'
import { deployImplementation } from '../proxy/implementation'
import HorizonProxiesModule from './HorizonProxies'

export default buildModule('HorizonStaking', (m) => {
  const { Controller, GraphProxyAdmin } = m.useModule(GraphPeripheryModule)
  const { HorizonStakingProxy } = m.useModule(HorizonProxiesModule)

  const subgraphServiceAddress = m.getParameter('subgraphServiceAddress')
  const maxThawingPeriod = m.getParameter('maxThawingPeriod')

  // Deploy HorizonStakingExtension - requires periphery and proxies to be registered in the controller
  const ExponentialRebates = m.library('ExponentialRebates', ExponentialRebatesArtifact)
  const HorizonStakingExtension = m.contract(
    'HorizonStakingExtension',
    HorizonStakingExtensionArtifact,
    [Controller, subgraphServiceAddress],
    {
      libraries: {
        ExponentialRebates: ExponentialRebates,
      },
      after: [GraphPeripheryModule, HorizonProxiesModule],
    },
  )

  // Deploy HorizonStaking implementation
  const HorizonStakingImplementation = deployImplementation(m, {
    name: 'HorizonStaking',
    artifact: HorizonStakingArtifact,
    constructorArgs: [Controller, HorizonStakingExtension, subgraphServiceAddress],
  })

  // Upgrade proxy to implementation contract
  const HorizonStaking = upgradeGraphProxy(m, GraphProxyAdmin, HorizonStakingProxy, HorizonStakingImplementation, {
    name: 'HorizonStaking',
    artifact: HorizonStakingArtifact,
  })
  m.call(HorizonStaking, 'setMaxThawingPeriod', [maxThawingPeriod])
  m.call(HorizonStaking, 'setAllowedLockedVerifier', [subgraphServiceAddress, true])

  return { HorizonStaking, HorizonStakingImplementation }
})

// Note that this module requires MigrateHorizonProxiesGovernorModule to be executed first
// The dependency is not made explicit to support the production workflow where the governor is a
// multisig owned by the Graph Council.
// For testnet, the dependency can be made explicit by having a parent module establish it.
export const MigrateHorizonStakingDeployerModule = buildModule('HorizonStakingDeployer', (m) => {
  const { Controller } = m.useModule(MigratePeripheryModule)

  const subgraphServiceAddress = m.getParameter('subgraphServiceAddress')
  const horizonStakingAddress = m.getParameter('horizonStakingAddress')

  const HorizonStakingProxy = m.contractAt('HorizonStakingProxy', GraphProxyArtifact, horizonStakingAddress)

  // Deploy HorizonStakingExtension - requires periphery and proxies to be registered in the controller
  const ExponentialRebates = m.library('ExponentialRebates', ExponentialRebatesArtifact)
  const HorizonStakingExtension = m.contract(
    'HorizonStakingExtension',
    HorizonStakingExtensionArtifact,
    [Controller, subgraphServiceAddress],
    {
      libraries: {
        ExponentialRebates: ExponentialRebates,
      },
    },
  )

  // Deploy HorizonStaking implementation
  const HorizonStakingImplementation = deployImplementation(m, {
    name: 'HorizonStaking',
    artifact: HorizonStakingArtifact,
    constructorArgs: [Controller, HorizonStakingExtension, subgraphServiceAddress],
  })

  return { HorizonStakingProxy, HorizonStakingImplementation }
})

export const MigrateHorizonStakingGovernorModule = buildModule('HorizonStakingGovernor', (m) => {
  const maxThawingPeriod = m.getParameter('maxThawingPeriod')
  const graphProxyAdminAddress = m.getParameter('graphProxyAdminAddress')
  const horizonStakingAddress = m.getParameter('horizonStakingAddress')
  const horizonStakingImplementationAddress = m.getParameter('horizonStakingImplementationAddress')
  const subgraphServiceAddress = m.getParameter('subgraphServiceAddress')

  const HorizonStakingImplementation = m.contractAt(
    'HorizonStakingImplementation',
    HorizonStakingArtifact,
    horizonStakingImplementationAddress,
  )
  const HorizonStakingProxy = m.contractAt('HorizonStakingProxy', GraphProxyArtifact, horizonStakingAddress)
  const GraphProxyAdmin = m.contractAt('GraphProxyAdmin', GraphProxyAdminArtifact, graphProxyAdminAddress)

  // Upgrade proxy to implementation contract
  const HorizonStaking = upgradeGraphProxy(m, GraphProxyAdmin, HorizonStakingProxy, HorizonStakingImplementation, {
    name: 'HorizonStaking',
    artifact: HorizonStakingArtifact,
  })
  m.call(HorizonStaking, 'setMaxThawingPeriod', [maxThawingPeriod])
  m.call(HorizonStaking, 'setAllowedLockedVerifier', [subgraphServiceAddress, true])

  return { HorizonStaking, HorizonStakingImplementation }
})
