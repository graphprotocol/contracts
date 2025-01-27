/* eslint-disable no-secrets/no-secrets */
import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import { ethers } from 'ethers'

import { MigrateGraphProxyAdminModule } from './GraphProxyAdmin'

import ControllerArtifact from '@graphprotocol/contracts/build/contracts/contracts/governance/Controller.sol/Controller.json'

export default buildModule('Controller', (m) => {
  const governor = m.getAccount(1)
  const pauseGuardian = m.getParameter('pauseGuardian')

  const Controller = m.contract('Controller', ControllerArtifact)
  m.call(Controller, 'setPauseGuardian', [pauseGuardian])
  m.call(Controller, 'setPaused', [false])
  m.call(Controller, 'transferOwnership', [governor])

  return { Controller }
})

export const MigrateControllerModule = buildModule('Controller', (m) => {
  const { GraphProxyAdmin } = m.useModule(MigrateGraphProxyAdminModule)

  const governor = m.getAccount(1)
  const controllerAddress = m.getParameter('controllerAddress')

  const Controller = m.contractAt('Controller', ControllerArtifact, controllerAddress)

  // GraphProxyAdmin was not registered in the controller in the original protocol
  m.call(Controller, 'setContractProxy',
    [ethers.keccak256(ethers.toUtf8Bytes('GraphProxyAdmin')), GraphProxyAdmin],
    { id: 'setContractProxy_GraphProxyAdmin', from: governor },
  )

  return { Controller }
})
