/* eslint-disable no-prototype-builtins */
/* eslint-disable @typescript-eslint/no-unsafe-return */
/* eslint-disable @typescript-eslint/no-unused-vars */
/* eslint-disable @typescript-eslint/no-explicit-any */
require('json5/lib/register')

import hre, { ignition } from 'hardhat'
import { IgnitionHelper } from 'hardhat-graph-protocol/sdk'

import DisputeManagerModule from '../ignition/modules/DisputeManager'
import HorizonModule from '@graphprotocol/horizon/ignition/modules/deploy'
import SubgraphServiceModule from '../ignition/modules/SubgraphService'
import SubgraphServiceProxiesModule from '../ignition/modules/Proxies'

// Horizon needs the SubgraphService proxy address before it can be deployed
// But SubgraphService and DisputeManager implementations need Horizon...
// So the deployment order is:
// - Deploy SubgraphService and DisputeManager proxies
// - Deploy Horizon
// - Deploy SubgraphService and DisputeManager implementations
async function main() {
  const SubgraphServiceConfig = IgnitionHelper.loadConfig('./ignition/configs/', 'subgraph-service', hre.network.name)
  const HorizonConfig = IgnitionHelper.loadConfig('./node_modules/@graphprotocol/horizon/ignition/configs', 'horizon', hre.network.name)

  // Deploy proxies
  const {
    DisputeManagerProxy,
    DisputeManagerProxyAdmin,
    SubgraphServiceProxy,
    SubgraphServiceProxyAdmin,
  } = await ignition.deploy(SubgraphServiceProxiesModule, {
    displayUi: true,
  })

  // Deploy Horizon
  const { Controller, GraphTallyCollector, L2Curation } = await ignition.deploy(HorizonModule, {
    displayUi: true,
    parameters: IgnitionHelper.patchConfig(HorizonConfig, {
      SubgraphService: {
        subgraphServiceProxyAddress: SubgraphServiceProxy.target as string,
      },
    }),
  })

  // Deploy DisputeManager implementation
  await ignition.deploy(DisputeManagerModule, {
    displayUi: true,
    parameters: IgnitionHelper.mergeConfigs(SubgraphServiceConfig, {
      DisputeManager: {
        controllerAddress: Controller.target as string,
        disputeManagerProxyAddress: DisputeManagerProxy.target as string,
        disputeManagerProxyAdminAddress: DisputeManagerProxyAdmin.target as string,
      },
    }),
  })

  // Deploy SubgraphService implementation
  await ignition.deploy(SubgraphServiceModule, {
    displayUi: true,
    parameters: IgnitionHelper.mergeConfigs(SubgraphServiceConfig, {
      SubgraphService: {
        controllerAddress: Controller.target as string,
        subgraphServiceProxyAddress: SubgraphServiceProxy.target as string,
        subgraphServiceProxyAdminAddress: SubgraphServiceProxyAdmin.target as string,
        disputeManagerAddress: DisputeManagerProxy.target as string,
        graphTallyCollectorAddress: GraphTallyCollector.target as string,
        curationAddress: L2Curation.target as string,
      },
    }),
  })
}

main().catch((error) => {
  console.error(error)
  process.exit(1)
})
