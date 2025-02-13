/* eslint-disable no-secrets/no-secrets */
import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import { ethers } from 'ethers'

import ControllerModule, { MigrateControllerDeployerModule } from './Controller'
import CurationModule, { MigrateCurationDeployerModule } from './Curation'
import EpochManagerModule, { MigrateEpochManagerModule } from './EpochManager'
import GraphProxyAdminModule, { MigrateGraphProxyAdminModule } from './GraphProxyAdmin'
import GraphTokenGatewayModule, { MigrateGraphTokenGatewayModule } from './GraphTokenGateway'
import GraphTokenModule, { MigrateGraphTokenModule } from './GraphToken'
import RewardsManagerModule, { MigrateRewardsManagerDeployerModule } from './RewardsManager'

export default buildModule('GraphHorizon_Periphery', (m) => {
  const { Controller } = m.useModule(ControllerModule)
  const { GraphProxyAdmin } = m.useModule(GraphProxyAdminModule)

  const { EpochManager } = m.useModule(EpochManagerModule)
  const { L2Curation } = m.useModule(CurationModule)
  const { RewardsManager } = m.useModule(RewardsManagerModule)
  const { L2GraphTokenGateway } = m.useModule(GraphTokenGatewayModule)
  const { L2GraphToken } = m.useModule(GraphTokenModule)

  m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('EpochManager')), EpochManager], { id: 'setContractProxy_EpochManager' })
  m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('RewardsManager')), RewardsManager], { id: 'setContractProxy_RewardsManager' })
  m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('GraphToken')), L2GraphToken], { id: 'setContractProxy_GraphToken' })
  m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('GraphTokenGateway')), L2GraphTokenGateway], { id: 'setContractProxy_GraphTokenGateway' })
  m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('GraphProxyAdmin')), GraphProxyAdmin], { id: 'setContractProxy_GraphProxyAdmin' })
  m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('Curation')), L2Curation], { id: 'setContractProxy_L2Curation' })

  return {
    Controller,
    EpochManager,
    L2Curation,
    GraphProxyAdmin,
    L2GraphToken,
    L2GraphTokenGateway,
    RewardsManager,
  }
})

export const MigratePeripheryModule = buildModule('GraphHorizon_Periphery', (m) => {
  const { L2CurationProxy: L2Curation, L2CurationImplementation } = m.useModule(MigrateCurationDeployerModule)
  const { RewardsManagerProxy: RewardsManager, RewardsManagerImplementation } = m.useModule(MigrateRewardsManagerDeployerModule)
  const { Controller } = m.useModule(MigrateControllerDeployerModule)
  const { GraphProxyAdmin } = m.useModule(MigrateGraphProxyAdminModule)
  const { EpochManager } = m.useModule(MigrateEpochManagerModule)
  const { L2GraphToken } = m.useModule(MigrateGraphTokenModule)
  const { L2GraphTokenGateway } = m.useModule(MigrateGraphTokenGatewayModule)

  // Load these contracts so they are available in the address book

  return {
    Controller,
    EpochManager,
    L2Curation,
    L2CurationImplementation,
    GraphProxyAdmin,
    L2GraphToken,
    L2GraphTokenGateway,
    RewardsManager,
    RewardsManagerImplementation,
  }
})
