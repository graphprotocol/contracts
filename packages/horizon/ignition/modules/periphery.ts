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
  const { RewardsManager } = m.useModule(RewardsManagerModule)
  const { GraphToken } = m.useModule(GraphTokenModule)
  const { Curation } = m.useModule(CurationModule)

  // Register contracts in the Controller
  const setProxyEpochManager = m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('EpochManager')), EpochManager], { id: 'setContractProxy_EpochManager' })
  const setProxyRewardsManager = m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('RewardsManager')), RewardsManager], { id: 'setContractProxy_RewardsManager' })
  const setProxyGraphToken = m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('GraphToken')), GraphToken], { id: 'setContractProxy_GraphToken' })
  const setProxyGraphTokenGateway = m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('GraphTokenGateway')), GraphTokenGateway], { id: 'setContractProxy_GraphTokenGateway' })
  // eslint-disable-next-line no-secrets/no-secrets
  const setProxyGraphProxyAdmin = m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('GraphProxyAdmin')), GraphProxyAdmin], { id: 'setContractProxy_GraphProxyAdmin' })
  const setProxyCuration = m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('Curation')), Curation], { id: 'setContractProxy_Curation' })

  // Deploy dummy contract to signal that all periphery contracts are registered
  const PeripheryRegistered = m.contract('Dummy', [], {
    after: [
      setProxyEpochManager,
      setProxyRewardsManager,
      setProxyGraphToken,
      setProxyGraphTokenGateway,
      setProxyGraphProxyAdmin,
      setProxyCuration,
    ],
  })

  return {
    BridgeEscrow,
    Controller,
    Curation,
    EpochManager,
    GraphProxyAdmin,
    GraphToken,
    GraphTokenGateway,
    RewardsManager,
    PeripheryRegistered,
  }
})
