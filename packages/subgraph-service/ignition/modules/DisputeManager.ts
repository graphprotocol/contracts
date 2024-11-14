import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import ProxyAdminArtifact from '@openzeppelin/contracts/build/contracts/ProxyAdmin.json'

// TODO: transfer ownership of ProxyAdmin???
export default buildModule('DisputeManager', (m) => {
  // Parameters - dynamically plugged in by the deploy script
  const controllerAddress = m.getParameter('controllerAddress')
  const disputeManagerProxyAddress = m.getParameter('disputeManagerProxyAddress')
  const disputeManagerProxyAdminAddress = m.getParameter('disputeManagerProxyAdminAddress')

  // Parameters - config file
  const arbitrator = m.getParameter('arbitrator')
  const disputePeriod = m.getParameter('disputePeriod')
  const disputeDeposit = m.getParameter('disputeDeposit')
  const fishermanRewardCut = m.getParameter('fishermanRewardCut')
  const maxSlashingCut = m.getParameter('maxSlashingCut')

  // Deploy implementation
  const DisputeManagerImplementation = m.contract('DisputeManager', [controllerAddress])

  // Upgrade implementation
  const DisputeManagerProxyAdmin = m.contractAt('ProxyAdmin', ProxyAdminArtifact, disputeManagerProxyAdminAddress)
  const encodedCall = m.encodeFunctionCall(DisputeManagerImplementation, 'initialize', [
    arbitrator,
    disputePeriod,
    disputeDeposit,
    fishermanRewardCut,
    maxSlashingCut,
  ])
  m.call(DisputeManagerProxyAdmin, 'upgradeAndCall', [disputeManagerProxyAddress, DisputeManagerImplementation, encodedCall])

  const DisputeManager = m.contractAt('DisputeManager', disputeManagerProxyAddress, { id: 'DisputeManager_Instance' })

  return { DisputeManager, DisputeManagerImplementation }
})
