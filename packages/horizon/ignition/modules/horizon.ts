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
    Curation,
  } = m.useModule(GraphPeripheryModule)
  m.useModule(GraphStakingModule)

  return {
    BridgeEscrow,
    Controller,
    Curation,
    EpochManager,
    GraphProxyAdmin,
    GraphTokenGateway,
    RewardsManager,
  }
})
