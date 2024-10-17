import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphPeripheryModule from '../periphery'
import HorizonProxiesModule from './HorizonProxies'

import TAPCollectorArtifact from '../../../build/contracts/contracts/payments/collectors/TAPCollector.sol/TAPCollector.json'

export default buildModule('TAPCollector', (m) => {
  const { Controller, PeripheryRegistered } = m.useModule(GraphPeripheryModule)
  const { HorizonRegistered } = m.useModule(HorizonProxiesModule)

  const name = m.getParameter('eip712Name')
  const version = m.getParameter('eip712Version')
  const revokeSignerThawingPeriod = m.getParameter('revokeSignerThawingPeriod')

  const TAPCollector = m.contract('TAPCollector', TAPCollectorArtifact, [name, version, Controller, revokeSignerThawingPeriod], { after: [PeripheryRegistered, HorizonRegistered] })

  return { TAPCollector }
})
