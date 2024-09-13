import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphPeripheryModule from '../periphery'
import HorizonProxiesModule from './HorizonProxies'

export default buildModule('TAPCollector', (m) => {
  const { Controller, PeripheryRegistered } = m.useModule(GraphPeripheryModule)
  const { HorizonRegistered } = m.useModule(HorizonProxiesModule)

  const name = m.getParameter('eip712Name')
  const version = m.getParameter('eip712Version')

  const TAPCollector = m.contract('TAPCollector', [name, version, Controller], { after: [PeripheryRegistered, HorizonRegistered] })

  return { TAPCollector }
})
