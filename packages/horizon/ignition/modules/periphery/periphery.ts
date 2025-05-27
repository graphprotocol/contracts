/* eslint-disable no-secrets/no-secrets */
import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import { ethers } from 'ethers'

import ControllerModule, { MigrateControllerDeployerModule } from './Controller'
import CurationModule, { MigrateCurationDeployerModule } from './Curation'
import EpochManagerModule, { MigrateEpochManagerModule } from './EpochManager'
import GNSModule, { MigrateL2GNSModule } from './GNS'
import GraphProxyAdminModule, { MigrateGraphProxyAdminModule } from './GraphProxyAdmin'
import GraphTokenGatewayModule, { MigrateGraphTokenGatewayModule } from './GraphTokenGateway'
import GraphTokenModule, { MigrateGraphTokenModule } from './GraphToken'
import RewardsManagerModule, { MigrateRewardsManagerDeployerModule } from './RewardsManager'

export default buildModule('GraphHorizon_Periphery', (m) => {
  const { Controller } = m.useModule(ControllerModule)
  const { GraphProxyAdmin } = m.useModule(GraphProxyAdminModule)

  const { EpochManager, EpochManagerImplementation } = m.useModule(EpochManagerModule)
  const { L2Curation, L2CurationImplementation } = m.useModule(CurationModule)
  const { L2GNS, L2GNSImplementation, SubgraphNFT } = m.useModule(GNSModule)
  const { RewardsManager, RewardsManagerImplementation } = m.useModule(RewardsManagerModule)
  const { L2GraphTokenGateway, L2GraphTokenGatewayImplementation } = m.useModule(GraphTokenGatewayModule)
  const { L2GraphToken, L2GraphTokenImplementation } = m.useModule(GraphTokenModule)

  m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('EpochManager')), EpochManager], { id: 'setContractProxy_EpochManager' })
  m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('RewardsManager')), RewardsManager], { id: 'setContractProxy_RewardsManager' })
  m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('GraphToken')), L2GraphToken], { id: 'setContractProxy_GraphToken' })
  m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('GraphTokenGateway')), L2GraphTokenGateway], { id: 'setContractProxy_GraphTokenGateway' })
  m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('GraphProxyAdmin')), GraphProxyAdmin], { id: 'setContractProxy_GraphProxyAdmin' })
  m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('Curation')), L2Curation], { id: 'setContractProxy_L2Curation' })
  m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('GNS')), L2GNS], { id: 'setContractProxy_L2GNS' })

  return {
    Controller,
    EpochManager,
    EpochManagerImplementation,
    L2Curation,
    L2CurationImplementation,
    L2GNS,
    L2GNSImplementation,
    SubgraphNFT,
    GraphProxyAdmin,
    L2GraphToken,
    L2GraphTokenImplementation,
    L2GraphTokenGateway,
    L2GraphTokenGatewayImplementation,
    RewardsManager,
    RewardsManagerImplementation,
  }
})

export const MigratePeripheryModule = buildModule('GraphHorizon_Periphery', (m) => {
  const { L2CurationProxy: L2Curation, L2CurationImplementation } = m.useModule(MigrateCurationDeployerModule)
  const { L2GNS, L2GNSImplementation, SubgraphNFT } = m.useModule(MigrateL2GNSModule)
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
    L2GNS,
    L2GNSImplementation,
    SubgraphNFT,
    GraphProxyAdmin,
    L2GraphToken,
    L2GraphTokenGateway,
    RewardsManager,
    RewardsManagerImplementation,
  }
})
