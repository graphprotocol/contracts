import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphPeripheryModule from './periphery'
import GraphStakingModule from './staking'

export default buildModule('GraphHorizon', (m) => {
  const {
    BridgeEscrow,
    Controller,
    EpochManager,
    GraphProxyAdmin,
    GraphTokenGateway,
    RewardsManager,
  } = m.useModule(GraphPeripheryModule)
  const { GraphToken } = m.useModule(GraphStakingModule)

  return {
    BridgeEscrow,
    Controller,
    EpochManager,
    GraphProxyAdmin,
    GraphToken,
    GraphTokenGateway,
    RewardsManager,
  }
})
