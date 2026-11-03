import ControllerArtifact from '@graphprotocol/graph-core/artifacts/contracts/governance/Controller.sol/Controller.json'
import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

export default buildModule('Controller', (m) => {
  const governor = m.getParameter('governor')
  const pauseGuardian = m.getParameter('pauseGuardian')

  const Controller = m.contract('Controller', ControllerArtifact)
  m.call(Controller, 'setPauseGuardian', [pauseGuardian])
  m.call(Controller, 'setPaused', [false])
  m.call(Controller, 'transferOwnership', [governor])

  return { Controller }
})
