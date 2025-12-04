import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import ProxyAdminArtifact from '@openzeppelin/contracts/build/contracts/ProxyAdmin.json'

/**
 * GraphIssuanceProxyAdmin - shared proxy admin for all issuance contracts
 *
 * This is a single instance of OpenZeppelin's ProxyAdmin contract that manages
 * upgrades for all issuance-related proxies (IssuanceAllocator, RewardsEligibilityOracle,
 * PilotAllocation).
 *
 * Uses standard OpenZeppelin ProxyAdmin (NOT Graph protocol's custom GraphProxyAdmin).
 * This ensures complete independence from the @graphprotocol/contracts package.
 *
 * The ProxyAdmin is owned by governance and can upgrade all issuance contract
 * implementations via governance transactions.
 */
export default buildModule('GraphIssuanceProxyAdmin', (m) => {
  const governor = m.getAccount(1)

  // Deploy ProxyAdmin with governor as initial owner
  // OZ ProxyAdmin constructor: constructor(address initialOwner)
  const GraphIssuanceProxyAdmin = m.contract('GraphIssuanceProxyAdmin', ProxyAdminArtifact, [governor])

  return { GraphIssuanceProxyAdmin }
})

// Module for connecting to existing GraphIssuanceProxyAdmin deployment
export const MigrateGraphIssuanceProxyAdminModule = buildModule('GraphIssuanceProxyAdminMigrate', (m) => {
  const graphIssuanceProxyAdminAddress = m.getParameter('graphIssuanceProxyAdminAddress')

  const GraphIssuanceProxyAdmin = m.contractAt(
    'GraphIssuanceProxyAdmin',
    ProxyAdminArtifact,
    graphIssuanceProxyAdminAddress,
  )

  return { GraphIssuanceProxyAdmin }
})
