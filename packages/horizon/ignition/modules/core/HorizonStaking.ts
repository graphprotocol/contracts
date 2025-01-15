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
  const isMigrate = m.getParameter('isMigrate')
  const governor = m.getAccount(1)
  const options = isMigrate ? { from: governor } : {}
  const upgradeCall = m.call(GraphProxyAdmin, 'upgrade', [HorizonStakingProxy, HorizonStakingImplementation], options)
  const acceptCall = m.call(GraphProxyAdmin, 'acceptProxy', [HorizonStakingImplementation, HorizonStakingProxy], { ...options, after: [upgradeCall] })

  // Load contract with implementation ABI
  const HorizonStaking = m.contractAt('HorizonStaking', HorizonStakingArtifact, HorizonStakingProxy, { after: [acceptCall], id: 'HorizonStaking_Instance' })
  m.call(HorizonStaking, 'setMaxThawingPeriod', [m.getParameter('maxThawingPeriod')], options)

  return { HorizonStakingProxy, HorizonStakingImplementation, HorizonStaking }
})
