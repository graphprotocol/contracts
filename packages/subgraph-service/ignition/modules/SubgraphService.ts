/* eslint-disable no-secrets/no-secrets */
import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import ProxyAdminArtifact from '@openzeppelin/contracts/build/contracts/ProxyAdmin.json'

// TODO: transfer ownership of ProxyAdmin???
export default buildModule('SubgraphService', (m) => {
  // Parameters - dynamically plugged in by the deploy script
  const controllerAddress = m.getParameter('controllerAddress')
  const subgraphServiceProxyAddress = m.getParameter('subgraphServiceProxyAddress')
  const subgraphServiceProxyAdminAddress = m.getParameter('subgraphServiceProxyAdminAddress')
  const disputeManagerAddress = m.getParameter('disputeManagerAddress')
  const tapCollectorAddress = m.getParameter('tapCollectorAddress')
  const curationAddress = m.getParameter('curationAddress')

  // Parameters - config file
  const minimumProvisionTokens = m.getParameter('minimumProvisionTokens')
  const maximumDelegationRatio = m.getParameter('maximumDelegationRatio')

  // Deploy implementation
  const SubgraphServiceImplementation = m.contract('SubgraphService', [controllerAddress, disputeManagerAddress, tapCollectorAddress, curationAddress])

  // Upgrade implementation
  const SubgraphServiceProxyAdmin = m.contractAt('TransparentUpgradeableProxy', ProxyAdminArtifact, subgraphServiceProxyAdminAddress)
  const encodedCall = m.encodeFunctionCall(SubgraphServiceImplementation, 'initialize', [
    minimumProvisionTokens,
    maximumDelegationRatio,
  ])
  m.call(SubgraphServiceProxyAdmin, 'upgradeAndCall', [subgraphServiceProxyAddress, SubgraphServiceImplementation, encodedCall])

  const SubgraphService = m.contractAt('SubgraphService', subgraphServiceProxyAddress, { id: 'SubgraphService_Instance' })

  return { SubgraphService, SubgraphServiceImplementation }
})
