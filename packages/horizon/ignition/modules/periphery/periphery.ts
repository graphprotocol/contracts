/* eslint-disable no-secrets/no-secrets */
import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import { ethers } from 'ethers'

import BridgeEscrowModule from './BridgeEscrow'
import ControllerModule from './Controller'
import CurationModule from './Curation'
import EpochManagerModule from './EpochManager'
import GraphProxyAdminModule from './GraphProxyAdmin'
import GraphTokenGatewayModule from './GraphTokenGateway'
import GraphTokenModule from './GraphToken'
import RewardsManagerModule from './RewardsManager'

export default buildModule('GraphHorizon_Periphery', (m) => {
  const { Controller } = m.useModule(ControllerModule)
  const { GraphProxyAdmin } = m.useModule(GraphProxyAdminModule)

  const { BridgeEscrow } = m.useModule(BridgeEscrowModule)
  const { EpochManager } = m.useModule(EpochManagerModule)
  const { L2Curation } = m.useModule(CurationModule)
  const { RewardsManager } = m.useModule(RewardsManagerModule)
  const { GraphTokenGateway } = m.useModule(GraphTokenGatewayModule)
  const { GraphToken } = m.useModule(GraphTokenModule)

  m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('EpochManager')), EpochManager], { id: 'setContractProxy_EpochManager' })
  m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('RewardsManager')), RewardsManager], { id: 'setContractProxy_RewardsManager' })
  m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('GraphToken')), GraphToken], { id: 'setContractProxy_GraphToken' })
  m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('GraphTokenGateway')), GraphTokenGateway], { id: 'setContractProxy_GraphTokenGateway' })
  m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('GraphProxyAdmin')), GraphProxyAdmin], { id: 'setContractProxy_GraphProxyAdmin' })
  m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('Curation')), L2Curation], { id: 'setContractProxy_L2Curation' })

  return {
    BridgeEscrow,
    Controller,
    EpochManager,
    L2Curation,
    GraphProxyAdmin,
    GraphToken,
    GraphTokenGateway,
    RewardsManager,
  }
})
