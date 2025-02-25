import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import { deployImplementation } from '@graphprotocol/horizon/ignition/modules/proxy/implementation'
import { upgradeTransparentUpgradeableProxy } from '@graphprotocol/horizon/ignition/modules/proxy/TransparentUpgradeableProxy'

import ProxyAdminArtifact from '@openzeppelin/contracts/build/contracts/ProxyAdmin.json'
import SubgraphServiceArtifact from '../../build/contracts/contracts/SubgraphService.sol/SubgraphService.json'
import TransparentUpgradeableProxyArtifact from '@openzeppelin/contracts/build/contracts/TransparentUpgradeableProxy.json'

export default buildModule('SubgraphService', (m) => {
  const deployer = m.getAccount(0)
  const governor = m.getParameter('governor')
  const pauseGuardian = m.getParameter('pauseGuardian')
  const controllerAddress = m.getParameter('controllerAddress')
  const subgraphServiceProxyAddress = m.getParameter('subgraphServiceProxyAddress')
  const subgraphServiceProxyAdminAddress = m.getParameter('subgraphServiceProxyAdminAddress')
  const disputeManagerProxyAddress = m.getParameter('disputeManagerProxyAddress')
  const graphTallyCollectorAddress = m.getParameter('graphTallyCollectorAddress')
  const curationProxyAddress = m.getParameter('curationProxyAddress')
  const minimumProvisionTokens = m.getParameter('minimumProvisionTokens')
  const maximumDelegationRatio = m.getParameter('maximumDelegationRatio')
  const stakeToFeesRatio = m.getParameter('stakeToFeesRatio')
  const maxPOIStaleness = m.getParameter('maxPOIStaleness')
  const curationCut = m.getParameter('curationCut')

  const SubgraphServiceProxyAdmin = m.contractAt('ProxyAdmin', ProxyAdminArtifact, subgraphServiceProxyAdminAddress)
  const SubgraphServiceProxy = m.contractAt('SubgraphServiceProxy', TransparentUpgradeableProxyArtifact, subgraphServiceProxyAddress)

  // Deploy implementation
  const SubgraphServiceImplementation = deployImplementation(m, {
    name: 'SubgraphService',
    constructorArgs: [controllerAddress, disputeManagerProxyAddress, graphTallyCollectorAddress, curationProxyAddress],
  })

  // Upgrade implementation
  const SubgraphService = upgradeTransparentUpgradeableProxy(m,
    SubgraphServiceProxyAdmin,
    SubgraphServiceProxy,
    SubgraphServiceImplementation, {
      name: 'SubgraphService',
      artifact: SubgraphServiceArtifact,
      initArgs: [
        deployer,
        minimumProvisionTokens,
        maximumDelegationRatio,
        stakeToFeesRatio,
      ],
    })

  const callSetPauseGuardian = m.call(SubgraphService, 'setPauseGuardian', [pauseGuardian, true])
  const callSetMaxPOIStaleness = m.call(SubgraphService, 'setMaxPOIStaleness', [maxPOIStaleness])
  const callSetCurationCut = m.call(SubgraphService, 'setCurationCut', [curationCut])

  m.call(SubgraphService, 'transferOwnership', [governor], { after: [callSetPauseGuardian, callSetMaxPOIStaleness, callSetCurationCut] })
  m.call(SubgraphServiceProxyAdmin, 'transferOwnership', [governor], { after: [callSetPauseGuardian, callSetMaxPOIStaleness, callSetCurationCut] })

  return {
    SubgraphService,
    SubgraphServiceImplementation,
  }
})
