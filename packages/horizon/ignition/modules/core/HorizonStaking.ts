import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import { deployImplementation } from '../proxy/implementation'
import { upgradeGraphProxyNoLoad } from '../proxy/GraphProxy'
import { ethers } from 'ethers'

import GraphPeripheryModule from '../periphery/periphery'
import HorizonProxiesModule from './HorizonProxies'

import ExponentialRebatesArtifact from '../../../build/contracts/contracts/staking/libraries/ExponentialRebates.sol/ExponentialRebates.json'
import HorizonStakingArtifact from '../../../build/contracts/contracts/staking/HorizonStaking.sol/HorizonStaking.json'
import HorizonStakingExtensionArtifact from '../../../build/contracts/contracts/staking/HorizonStakingExtension.sol/HorizonStakingExtension.json'

export default buildModule('HorizonStaking', (m) => {
  const { Controller, GraphProxyAdmin } = m.useModule(GraphPeripheryModule)
  const { HorizonStakingProxy } = m.useModule(HorizonProxiesModule)

  const subgraphServiceAddress = m.getParameter('subgraphServiceAddress')

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

  return { HorizonStaking }
})

// export const UpgradeHorizonStakingModule = buildModule('HorizonStaking', (m) => {
//   const { Controller, GraphProxyAdmin } = m.useModule(GraphPeripheryModule)
//   const { HorizonStakingProxy } = m.useModule(HorizonProxiesModule)
//   const { HorizonStakingExtension } = m.useModule(HorizonStakingExtensionModule)

//   const subgraphServiceAddress = m.getParameter('subgraphServiceAddress')

//   // Deploy HorizonStaking implementation
//   const HorizonStakingImplementation = m.contract('HorizonStaking',
//     HorizonStakingArtifact,
//     [
//       Controller,
//       HorizonStakingExtension,
//       subgraphServiceAddress,
//     ],
//     {
//       after: [GraphPeripheryModule, HorizonProxiesModule],
//     },
//   )

//   // Upgrade proxy to implementation contract
//   const isMigrate = m.getParameter('isMigrate')
//   const governor = m.getAccount(1)
//   const options = isMigrate ? { from: governor } : {}
//   const upgradeCall = m.call(GraphProxyAdmin, 'upgrade', [HorizonStakingProxy, HorizonStakingImplementation], options)
//   const acceptCall = m.call(GraphProxyAdmin, 'acceptProxy', [HorizonStakingImplementation, HorizonStakingProxy], { ...options, after: [upgradeCall] })

//   // Load contract with implementation ABI
//   const HorizonStaking = m.contractAt('HorizonStaking', HorizonStakingArtifact, HorizonStakingProxy, { after: [acceptCall], id: 'HorizonStaking_Instance' })
//   m.call(HorizonStaking, 'setMaxThawingPeriod', [m.getParameter('maxThawingPeriod')], options)

//   return { HorizonStakingProxy, HorizonStakingImplementation, HorizonStaking }
// })
