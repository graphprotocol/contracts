import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import { deployImplementation } from '@graphprotocol/horizon/ignition/modules/proxy/implementation'
import { upgradeTransparentUpgradeableProxy } from '@graphprotocol/horizon/ignition/modules/proxy/TransparentUpgradeableProxy'

import DisputeManagerArtifact from '../../build/contracts/contracts/DisputeManager.sol/DisputeManager.json'
import ProxyAdminArtifact from '@openzeppelin/contracts/build/contracts/ProxyAdmin.json'
import TransparentUpgradeableProxyArtifact from '@openzeppelin/contracts/build/contracts/TransparentUpgradeableProxy.json'

export default buildModule('DisputeManager', (m) => {
  const deployer = m.getAccount(0)
  const governor = m.getParameter('governor')
  const controllerAddress = m.getParameter('controllerAddress')
  const subgraphServiceProxyAddress = m.getParameter('subgraphServiceProxyAddress')
  const disputeManagerProxyAddress = m.getParameter('disputeManagerProxyAddress')
  const disputeManagerProxyAdminAddress = m.getParameter('disputeManagerProxyAdminAddress')
  const arbitrator = m.getParameter('arbitrator')
  const disputePeriod = m.getParameter('disputePeriod')
  const disputeDeposit = m.getParameter('disputeDeposit')
  const fishermanRewardCut = m.getParameter('fishermanRewardCut')
  const maxSlashingCut = m.getParameter('maxSlashingCut')

  const DisputeManagerProxyAdmin = m.contractAt('ProxyAdmin', ProxyAdminArtifact, disputeManagerProxyAdminAddress)
  const DisputeManagerProxy = m.contractAt('DisputeManagerProxy', TransparentUpgradeableProxyArtifact, disputeManagerProxyAddress)

  // Deploy implementation
  const DisputeManagerImplementation = deployImplementation(m, {
    name: 'DisputeManager',
    constructorArgs: [controllerAddress],
  })

  // Upgrade implementation
  const DisputeManager = upgradeTransparentUpgradeableProxy(m,
    DisputeManagerProxyAdmin,
    DisputeManagerProxy,
    DisputeManagerImplementation, {
      name: 'DisputeManager',
      artifact: DisputeManagerArtifact,
      initArgs: [
        deployer,
        arbitrator,
        disputePeriod,
        disputeDeposit,
        fishermanRewardCut,
        maxSlashingCut,
      ],
    })

  const callSetSubgraphService = m.call(DisputeManager, 'setSubgraphService', [subgraphServiceProxyAddress])

  m.call(DisputeManager, 'transferOwnership', [governor], { after: [callSetSubgraphService] })
  m.call(DisputeManagerProxyAdmin, 'transferOwnership', [governor], { after: [callSetSubgraphService] })

  return {
    DisputeManager,
    DisputeManagerImplementation,
  }
})
