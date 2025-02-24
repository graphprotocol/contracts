/* eslint-disable no-secrets/no-secrets */
import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import { ethers } from 'ethers'

import ControllerArtifact from '@graphprotocol/contracts/build/contracts/contracts/governance/Controller.sol/Controller.json'

export default buildModule('Controller', (m) => {
  const governor = m.getParameter('governor')
  const pauseGuardian = m.getParameter('pauseGuardian')

  const Controller = m.contract('Controller', ControllerArtifact)
  m.call(Controller, 'setPauseGuardian', [pauseGuardian])
  m.call(Controller, 'setPaused', [false])
  m.call(Controller, 'transferOwnership', [governor])

  return { Controller }
})

export const MigrateControllerDeployerModule = buildModule('ControllerDeployer', (m) => {
  const controllerAddress = m.getParameter('controllerAddress')

  const Controller = m.contractAt('Controller', ControllerArtifact, controllerAddress)

  return { Controller }
})

export const MigrateControllerGovernorModule = buildModule('ControllerGovernor', (m) => {
  const { Controller } = m.useModule(MigrateControllerDeployerModule)

  const graphProxyAdminAddress = m.getParameter('graphProxyAdminAddress')

  // GraphProxyAdmin was not registered in the controller in the original protocol
  m.call(Controller, 'setContractProxy',
    [ethers.keccak256(ethers.toUtf8Bytes('GraphProxyAdmin')), graphProxyAdminAddress],
    { id: 'setContractProxy_GraphProxyAdmin' },
  )

  return { Controller }
})
