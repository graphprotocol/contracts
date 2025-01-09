import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import { deployWithGraphProxy } from '../proxy/GraphProxy'

import ControllerModule from './Controller'
import EpochManagerArtifact from '@graphprotocol/contracts/build/contracts/contracts/epochs/EpochManager.sol/EpochManager.json'

export default buildModule('EpochManager', (m) => {
  const isMigrate = m.getParameter('isMigrate', false)

  let EpochManager
  if (isMigrate) {
    const epochManagerProxyAddress = m.getParameter('epochManagerProxyAddress')
    EpochManager = m.contractAt('EpochManager', EpochManagerArtifact, epochManagerProxyAddress)
  } else {
    const { Controller } = m.useModule(ControllerModule)

    const epochLength = m.getParameter('epochLength')

    EpochManager = deployWithGraphProxy(m, {
      name: 'EpochManager',
      artifact: EpochManagerArtifact,
      args: [Controller, epochLength],
    }).instance
  }

  return { EpochManager }
})
