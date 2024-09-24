import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphPeripheryModule from '../periphery'
import HorizonProxiesModule from './HorizonProxies'
import HorizonStakingExtensionModule from './HorizonStakingExtension'

import HorizonStakingArtifact from '../../../build/contracts/contracts/staking/HorizonStaking.sol/HorizonStaking.json'

export default buildModule('HorizonStaking', (m) => {
  const { Controller, GraphProxyAdmin, PeripheryRegistered } = m.useModule(GraphPeripheryModule)
  const { HorizonStakingProxy, HorizonRegistered } = m.useModule(HorizonProxiesModule)
  const { HorizonStakingExtension } = m.useModule(HorizonStakingExtensionModule)

  const subgraphServiceAddress = m.getParameter('subgraphServiceAddress')

  // Deploy HorizonStaking implementation
  const HorizonStakingImplementation = m.contract('HorizonStaking',
    HorizonStakingArtifact,
    [
      Controller,
      HorizonStakingExtension,
      subgraphServiceAddress,
    ],
    {
      after: [PeripheryRegistered, HorizonRegistered],
    },
  )

  // Upgrade proxy to implementation contract
  const upgradeCall = m.call(GraphProxyAdmin, 'upgrade', [HorizonStakingProxy, HorizonStakingImplementation])
  const acceptCall = m.call(GraphProxyAdmin, 'acceptProxy', [HorizonStakingImplementation, HorizonStakingProxy], { after: [upgradeCall] })

  // Load contract with implementation ABI
  const HorizonStaking = m.contractAt('HorizonStaking', HorizonStakingArtifact, HorizonStakingProxy, { after: [acceptCall], id: 'HorizonStaking_Instance' })
  m.call(HorizonStaking, 'setMaxThawingPeriod', [m.getParameter('maxThawingPeriod')])

  return { HorizonStakingProxy, HorizonStakingImplementation, HorizonStaking }
})
