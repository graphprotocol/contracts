import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import { deployImplementation } from '@graphprotocol/horizon/ignition/modules/proxy/implementation'
import { upgradeTransparentUpgradeableProxy } from '@graphprotocol/horizon/ignition/modules/proxy/TransparentUpgradeableProxy'

import ProxyAdminArtifact from '@openzeppelin/contracts/build/contracts/ProxyAdmin.json'
import TransparentUpgradeableProxyArtifact from '@openzeppelin/contracts/build/contracts/TransparentUpgradeableProxy.json'

export default buildModule('DisputeManager', (m) => {
  const governor = m.getParameter('governor')
  const controllerAddress = m.getParameter('controllerAddress')
  const disputeManagerAddress = m.getParameter('disputeManagerAddress')
  const disputeManagerProxyAdminAddress = m.getParameter('disputeManagerProxyAdminAddress')
  const arbitrator = m.getParameter('arbitrator')
  const disputePeriod = m.getParameter('disputePeriod')
  const disputeDeposit = m.getParameter('disputeDeposit')
  const fishermanRewardCut = m.getParameter('fishermanRewardCut')
  const maxSlashingCut = m.getParameter('maxSlashingCut')

  const DisputeManagerProxyAdmin = m.contractAt('ProxyAdmin', ProxyAdminArtifact, disputeManagerProxyAdminAddress)
  const DisputeManagerProxy = m.contractAt('DisputeManager', TransparentUpgradeableProxyArtifact, disputeManagerAddress)

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
      initArgs: [
        arbitrator,
        disputePeriod,
        disputeDeposit,
        fishermanRewardCut,
        maxSlashingCut,
      ],
    })

  m.call(DisputeManagerProxyAdmin, 'transferOwnership', [governor], { after: [DisputeManager] })

  return { DisputeManager, DisputeManagerImplementation }
})
