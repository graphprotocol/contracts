/* eslint-disable no-prototype-builtins */
/* eslint-disable @typescript-eslint/no-unsafe-return */
/* eslint-disable @typescript-eslint/no-unused-vars */
/* eslint-disable @typescript-eslint/no-explicit-any */
require('json5/lib/register')

import hre, { ignition } from 'hardhat'
import { IgnitionHelper } from 'hardhat-graph-protocol/sdk'

import MigrateStep1 from '../ignition/modules/migrate/migrate-1'
import MigrateStep2 from '../ignition/modules/migrate/migrate-2'

// Horizon needs the SubgraphService proxy address before it can be deployed
// But SubgraphService and DisputeManager implementations need Horizon...
// So the deployment order is:
// - Deploy SubgraphService and DisputeManager proxies
// - Deploy Horizon
// - Deploy SubgraphService and DisputeManager implementations
async function main() {
  const SubgraphServiceConfig = IgnitionHelper.loadConfig('./ignition/configs/', 'subgraph-service', hre.network.name)

  // Deploy proxies
  const {
    DisputeManagerProxy,
    DisputeManagerProxyAdmin,
    SubgraphServiceProxy,
    SubgraphServiceProxyAdmin,
  } = await ignition.deploy(MigrateStep1, {
    displayUi: true,
  })

  const PatchedSubgraphServiceConfig = IgnitionHelper.mergeConfigs(SubgraphServiceConfig, {
    $global: {
      subgraphServiceAddress: SubgraphServiceProxy.target as string,
      subgraphServiceProxyAdminAddress: SubgraphServiceProxyAdmin.target as string,
      disputeManagerAddress: DisputeManagerProxy.target as string,
      disputeManagerProxyAdminAddress: DisputeManagerProxyAdmin.target as string,
    },
  })

  await ignition.deploy(MigrateStep2, {
    displayUi: true,
    parameters: PatchedSubgraphServiceConfig,
    deploymentId: `subgraph-service-${hre.network.name}`,
  })
}
main().catch((error) => {
  console.error(error)
  process.exit(1)
})
