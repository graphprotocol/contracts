import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphPeripheryModule, { MigratePeripheryModule } from '../periphery/periphery'
import HorizonProxiesModule, { MigrateHorizonProxiesModule } from './HorizonProxies'

import ControllerArtifact from '@graphprotocol/contracts/build/contracts/contracts/governance/Controller.sol/Controller.json'
import TAPCollectorArtifact from '../../../build/contracts/contracts/payments/collectors/TAPCollector.sol/TAPCollector.json'

export default buildModule('TAPCollector', (m) => {
  const { Controller } = m.useModule(GraphPeripheryModule)

  const name = m.getParameter('eip712Name')
  const version = m.getParameter('eip712Version')
  const revokeSignerThawingPeriod = m.getParameter('revokeSignerThawingPeriod')

  const TAPCollector = m.contract(
    'TAPCollector',
    TAPCollectorArtifact,
    [name, version, Controller, revokeSignerThawingPeriod],
    { after: [GraphPeripheryModule, HorizonProxiesModule] },
  )

  return { TAPCollector }
})

export const MigrateTAPCollectorModule = buildModule('TAPCollector', (m) => {
  const controllerAddress = m.getParameter('controllerAddress')
  const name = m.getParameter('eip712Name')
  const version = m.getParameter('eip712Version')
  const revokeSignerThawingPeriod = m.getParameter('revokeSignerThawingPeriod')

  const Controller = m.contractAt('Controller', ControllerArtifact, controllerAddress)

  const TAPCollector = m.contract(
    'TAPCollector',
    TAPCollectorArtifact,
    [name, version, Controller, revokeSignerThawingPeriod],
    { after: [MigratePeripheryModule, MigrateHorizonProxiesModule] },
  )

  return { TAPCollector }
})
