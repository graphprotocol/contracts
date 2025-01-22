import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphPeripheryModule from '../periphery'
import HorizonProxiesModule from './HorizonProxies'

import ExponentialRebatesArtifact from '../../../build/contracts/contracts/staking/libraries/ExponentialRebates.sol/ExponentialRebates.json'
import HorizonStakingExtensionArtifact from '../../../build/contracts/contracts/staking/HorizonStakingExtension.sol/HorizonStakingExtension.json'

export default buildModule('HorizonStakingExtension', (m) => {
  const { Controller } = m.useModule(GraphPeripheryModule)

  const subgraphServiceAddress = m.getParameter('subgraphServiceAddress')

  const ExponentialRebates = m.library('ExponentialRebates', ExponentialRebatesArtifact)
  const HorizonStakingExtension = m.contract('HorizonStakingExtension',
    HorizonStakingExtensionArtifact,
    [Controller, subgraphServiceAddress], {
      libraries: {
        ExponentialRebates: ExponentialRebates,
      },
      after: [GraphPeripheryModule, HorizonProxiesModule],
    })

  return { HorizonStakingExtension }
})
