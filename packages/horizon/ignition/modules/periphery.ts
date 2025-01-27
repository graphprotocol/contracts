import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import { ethers } from 'ethers'

import BridgeEscrowModule from './periphery/BridgeEscrow'
import ControllerModule from './periphery/Controller'
import CurationModule from './periphery/Curation'
import EpochManagerModule from './periphery/EpochManager'
import GraphProxyAdminModule from './periphery/GraphProxyAdmin'
import GraphTokenGatewayModule from './periphery/GraphTokenGateway'
import GraphTokenModule from './periphery/GraphToken'
import RewardsManagerModule from './periphery/RewardsManager'

export default buildModule('GraphHorizon_Periphery', (m) => {
  const { BridgeEscrow } = m.useModule(BridgeEscrowModule)
  const { Controller } = m.useModule(ControllerModule)
  const { EpochManager } = m.useModule(EpochManagerModule)
  const { GraphProxyAdmin } = m.useModule(GraphProxyAdminModule)
  const { GraphTokenGateway } = m.useModule(GraphTokenGatewayModule)
  const { GraphToken } = m.useModule(GraphTokenModule)

  const { instance: RewardsManager } = m.useModule(RewardsManagerModule)
  const { instance: Curation } = m.useModule(CurationModule)

  const isMigrate = m.getParameter('isMigrate', false)

  if (!isMigrate) {
    // Register contracts in the Controller
    m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('EpochManager')), EpochManager], { id: 'setContractProxy_EpochManager' })
    m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('RewardsManager')), RewardsManager], { id: 'setContractProxy_RewardsManager' })
    m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('GraphToken')), GraphToken], { id: 'setContractProxy_GraphToken' })
    m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('GraphTokenGateway')), GraphTokenGateway], { id: 'setContractProxy_GraphTokenGateway' })
    // eslint-disable-next-line no-secrets/no-secrets
    m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('GraphProxyAdmin')), GraphProxyAdmin], { id: 'setContractProxy_GraphProxyAdmin' })
    m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('Curation')), Curation], { id: 'setContractProxy_Curation' })
  } else {
    // TODO: Remove if not needed
    const governor = m.getAccount(1)
    // eslint-disable-next-line no-secrets/no-secrets
    m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('GraphProxyAdmin')), GraphProxyAdmin], { id: 'setContractProxy_GraphProxyAdmin', from: governor })
  }

  return {
    BridgeEscrow,
    Controller,
    Curation,
    EpochManager,
    GraphProxyAdmin,
    GraphToken,
    GraphTokenGateway,
    RewardsManager,
  }
})
