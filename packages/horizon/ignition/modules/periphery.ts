import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import BridgeEscrowModule from './periphery/BridgeEscrow'
import ControllerModule from './periphery/Controller'
import EpochManagerModule from './periphery/EpochManager'
import GraphProxyAdminModule from './periphery/GraphProxyAdmin'
import GraphTokenGatewayModule from './periphery/GraphTokenGateway'
import RewardsManagerModule from './periphery/RewardsManager'

// GraphTokenGateway
export default buildModule('GraphHorizon_Periphery', (m) => {
  const { BridgeEscrow } = m.useModule(BridgeEscrowModule)
  const { Controller } = m.useModule(ControllerModule)
  const { EpochManager } = m.useModule(EpochManagerModule)
  const { GraphProxyAdmin } = m.useModule(GraphProxyAdminModule)
  const { GraphTokenGateway } = m.useModule(GraphTokenGatewayModule)
  const { RewardsManager } = m.useModule(RewardsManagerModule)

  return {
    BridgeEscrow,
    Controller,
    EpochManager,
    GraphProxyAdmin,
    GraphTokenGateway,
    RewardsManager,
  }
})
