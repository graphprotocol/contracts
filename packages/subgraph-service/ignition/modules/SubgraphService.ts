import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import { deployImplementation } from '@graphprotocol/horizon/ignition/modules/proxy/implementation'
import { upgradeTransparentUpgradeableProxy } from '@graphprotocol/horizon/ignition/modules/proxy/TransparentUpgradeableProxy'

import ProxyAdminArtifact from '@openzeppelin/contracts/build/contracts/ProxyAdmin.json'
import SubgraphServiceArtifact from '../../build/contracts/contracts/SubgraphService.sol/SubgraphService.json'
import TransparentUpgradeableProxyArtifact from '@openzeppelin/contracts/build/contracts/TransparentUpgradeableProxy.json'

export default buildModule('SubgraphService', (m) => {
  const governor = m.getParameter('governor')
  const controllerAddress = m.getParameter('controllerAddress')
  const subgraphServiceProxyAddress = m.getParameter('subgraphServiceProxyAddress')
  const subgraphServiceProxyAdminAddress = m.getParameter('subgraphServiceProxyAdminAddress')
  const disputeManagerProxyAddress = m.getParameter('disputeManagerProxyAddress')
  const graphTallyCollectorAddress = m.getParameter('graphTallyCollectorAddress')
  const curationAddress = m.getParameter('curationAddress')
  const minimumProvisionTokens = m.getParameter('minimumProvisionTokens')
  const maximumDelegationRatio = m.getParameter('maximumDelegationRatio')
  const stakeToFeesRatio = m.getParameter('stakeToFeesRatio')

  const SubgraphServiceProxyAdmin = m.contractAt('ProxyAdmin', ProxyAdminArtifact, subgraphServiceProxyAdminAddress)
  const SubgraphServiceProxy = m.contractAt('SubgraphServiceProxy', TransparentUpgradeableProxyArtifact, subgraphServiceProxyAddress)

  // Deploy implementation
  const SubgraphServiceImplementation = deployImplementation(m, {
    name: 'SubgraphService',
    constructorArgs: [controllerAddress, disputeManagerProxyAddress, graphTallyCollectorAddress, curationAddress],
  })

  // Upgrade implementation
  const SubgraphService = upgradeTransparentUpgradeableProxy(m,
    SubgraphServiceProxyAdmin,
    SubgraphServiceProxy,
    SubgraphServiceImplementation, {
      name: 'SubgraphService',
      artifact: SubgraphServiceArtifact,
      initArgs: [
        minimumProvisionTokens,
        maximumDelegationRatio,
        stakeToFeesRatio,
      ],
    })

  m.call(SubgraphServiceProxyAdmin, 'transferOwnership', [governor], { after: [SubgraphService] })

  return {
    Transparent_Proxy_SubgraphService: SubgraphService,
    Implementation_SubgraphService: SubgraphServiceImplementation,
  }
})
