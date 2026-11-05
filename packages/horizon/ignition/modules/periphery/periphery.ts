import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import type { Artifact } from '@nomicfoundation/ignition-core'
import { ethers } from 'ethers'

import ControllerModule from './Controller'
import { buildCurationModule } from './Curation'
import EpochManagerModule from './EpochManager'
import { buildGNSModule } from './GNS'
import GraphProxyAdminModule from './GraphProxyAdmin'
import GraphTokenModule from './GraphToken'
import GraphTokenGatewayModule from './GraphTokenGateway'
import RewardsManagerModule from './RewardsManager'

// L2Curation and L2GNS artifacts come from subgraph-service. Curation is built once and shared with GNS,
// because Ignition rejects two different modules with the same id.
export function buildPeripheryModule(artifacts: { L2Curation: Artifact; L2GNS: Artifact }) {
  const CurationModule = buildCurationModule(artifacts.L2Curation)
  const GNSModule = buildGNSModule(artifacts.L2GNS, CurationModule)

  return buildModule('GraphHorizon_Periphery', (m) => {
    const { Controller } = m.useModule(ControllerModule)
    const { GraphProxyAdmin } = m.useModule(GraphProxyAdminModule)

    const { EpochManager, EpochManagerImplementation } = m.useModule(EpochManagerModule)
    const { L2Curation, L2CurationImplementation } = m.useModule(CurationModule)
    const { L2GNS, L2GNSImplementation, SubgraphNFT } = m.useModule(GNSModule)
    const { RewardsManager, RewardsManagerImplementation } = m.useModule(RewardsManagerModule)
    const { L2GraphTokenGateway, L2GraphTokenGatewayImplementation } = m.useModule(GraphTokenGatewayModule)
    const { L2GraphToken, L2GraphTokenImplementation } = m.useModule(GraphTokenModule)

    const disputeManagerAddress = m.getParameter('disputeManagerAddress')

    m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('EpochManager')), EpochManager], {
      id: 'setContractProxy_EpochManager',
    })
    m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('RewardsManager')), RewardsManager], {
      id: 'setContractProxy_RewardsManager',
    })
    m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('GraphToken')), L2GraphToken], {
      id: 'setContractProxy_GraphToken',
    })
    m.call(
      Controller,
      'setContractProxy',
      [ethers.keccak256(ethers.toUtf8Bytes('GraphTokenGateway')), L2GraphTokenGateway],
      { id: 'setContractProxy_GraphTokenGateway' },
    )
    m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('GraphProxyAdmin')), GraphProxyAdmin], {
      id: 'setContractProxy_GraphProxyAdmin',
    })
    m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('Curation')), L2Curation], {
      id: 'setContractProxy_L2Curation',
    })
    m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('GNS')), L2GNS], {
      id: 'setContractProxy_L2GNS',
    })
    m.call(
      Controller,
      'setContractProxy',
      [ethers.keccak256(ethers.toUtf8Bytes('DisputeManager')), disputeManagerAddress],
      {
        id: 'setContractProxy_DisputeManager',
      },
    )

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
}
