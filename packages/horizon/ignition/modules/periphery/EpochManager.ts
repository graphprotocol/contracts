import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import { deployWithGraphProxy } from '../proxy/GraphProxy'

import ControllerModule from './Controller'
import EpochManagerArtifact from '@graphprotocol/contracts/build/contracts/contracts/epochs/EpochManager.sol/EpochManager.json'

export default buildModule('EpochManager', (m) => {
  const { Controller } = m.useModule(ControllerModule)

  const epochLength = m.getParameter('epochLength')

  const { instance: EpochManager } = deployWithGraphProxy(m, {
    name: 'EpochManager',
    artifact: EpochManagerArtifact,
    args: [Controller, epochLength],
  })

  return { EpochManager }
})
