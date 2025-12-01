import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphProxyAdminArtifact from '../../../../contracts/artifacts/contracts/upgrades/GraphProxyAdmin.sol/GraphProxyAdmin.json'

/**
 * GraphProxyAdmin2 - Shared proxy admin for issuance contracts
 *
 * This is a second instance of GraphProxyAdmin, used specifically for
 * issuance contracts (IssuanceAllocator, RewardsEligibilityOracle, PilotAllocation).
 *
 * The original GraphProxyAdmin (in horizon package) manages legacy contracts.
 * This GraphProxyAdmin2 manages all issuance-related proxies.
 */
export default buildModule('GraphProxyAdmin2', (m) => {
  const governor = m.getAccount(1)

  const GraphProxyAdmin2 = m.contract('GraphProxyAdmin2', GraphProxyAdminArtifact)
  m.call(GraphProxyAdmin2, 'transferOwnership', [governor])

  return { GraphProxyAdmin2 }
})

// Module for connecting to existing GraphProxyAdmin2 deployment
export const MigrateGraphProxyAdmin2Module = buildModule('GraphProxyAdmin2Migrate', (m) => {
  const graphProxyAdmin2Address = m.getParameter('graphProxyAdmin2Address')

  const GraphProxyAdmin2 = m.contractAt('GraphProxyAdmin2', GraphProxyAdminArtifact, graphProxyAdmin2Address)

  return { GraphProxyAdmin2 }
})
