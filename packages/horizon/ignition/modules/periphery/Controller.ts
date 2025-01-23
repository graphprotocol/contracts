import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import ControllerArtifact from '@graphprotocol/contracts/build/contracts/contracts/governance/Controller.sol/Controller.json'

export default buildModule('Controller', (m) => {
  const governor = m.getParameter('governor')
  const pauseGuardian = m.getParameter('pauseGuardian')

  const Controller = m.contract('Controller', ControllerArtifact)
  m.call(Controller, 'setPauseGuardian', [pauseGuardian])
  m.call(Controller, 'transferOwnership', [governor])
  m.call(Controller, 'setPaused', [false])

  return { Controller }
})
