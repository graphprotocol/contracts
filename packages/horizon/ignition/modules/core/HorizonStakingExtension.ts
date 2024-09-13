import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphPeripheryModule from '../periphery'
import HorizonProxiesModule from './HorizonProxies'

export default buildModule('HorizonStakingExtension', (m) => {
  const { Controller, PeripheryRegistered } = m.useModule(GraphPeripheryModule)
  const { HorizonRegistered } = m.useModule(HorizonProxiesModule)

  const subgraphServiceAddress = m.getParameter('subgraphServiceAddress')

  const ExponentialRebates = m.library('ExponentialRebates')
  const HorizonStakingExtension = m.contract('HorizonStakingExtension',
    [Controller, subgraphServiceAddress], {
      libraries: {
        ExponentialRebates: ExponentialRebates,
      },
      after: [PeripheryRegistered, HorizonRegistered],
    })

  return { HorizonStakingExtension }
})
