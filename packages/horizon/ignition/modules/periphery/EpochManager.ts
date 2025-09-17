import EpochManagerArtifact from '@graphprotocol/contracts/artifacts/contracts/epochs/EpochManager.sol/EpochManager.json'
import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import { deployWithGraphProxy } from '../proxy/GraphProxy'
import ControllerModule from './Controller'
import GraphProxyAdminModule from './GraphProxyAdmin'

export default buildModule('EpochManager', (m) => {
  const { Controller } = m.useModule(ControllerModule)
  const { GraphProxyAdmin } = m.useModule(GraphProxyAdminModule)

  const epochLength = m.getParameter('epochLength')

  const { proxy: EpochManager, implementation: EpochManagerImplementation } = deployWithGraphProxy(m, GraphProxyAdmin, {
    name: 'EpochManager',
    artifact: EpochManagerArtifact,
    initArgs: [Controller, epochLength],
  })

  return { EpochManager, EpochManagerImplementation }
})

export const MigrateEpochManagerModule = buildModule('EpochManager', (m) => {
  const epochManagerAddress = m.getParameter('epochManagerAddress')
  const epochManagerImplementationAddress = m.getParameter('epochManagerImplementationAddress')

  const EpochManager = m.contractAt('EpochManager', EpochManagerArtifact, epochManagerAddress)
  const EpochManagerImplementation = m.contractAt(
    'EpochManagerAddressBook',
    EpochManagerArtifact,
    epochManagerImplementationAddress,
  )

  return { EpochManager, EpochManagerImplementation }
})
