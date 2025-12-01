import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import DirectAllocationArtifact from '../../../artifacts/contracts/allocate/DirectAllocation.sol/DirectAllocation.json'
import { deployImplementation } from './proxy/implementation'
import { deployWithTransparentUpgradeableProxy } from './proxy/TransparentUpgradeableProxy'

export default buildModule('PilotAllocation', (m) => {
  const governor = m.getAccount(1)
  const graphTokenAddress = m.getParameter('graphTokenAddress')

  // Deploy DirectAllocation implementation (contract name is DirectAllocation)
  const PilotAllocationImplementation = deployImplementation(m, {
    name: 'PilotAllocation',
    artifact: DirectAllocationArtifact,
    constructorArgs: [graphTokenAddress],
  })

  // Deploy proxy (deployed as PilotAllocation)
  const { proxy: PilotAllocationProxy, proxyAdmin: PilotAllocationProxyAdmin } = deployWithTransparentUpgradeableProxy(
    m,
    {
      name: 'PilotAllocation',
      artifact: DirectAllocationArtifact,
      constructorArgs: [graphTokenAddress],
      initArgs: [governor],
    },
  )

  // Transfer ProxyAdmin ownership to governor
  m.call(PilotAllocationProxyAdmin, 'transferOwnership', [governor], { after: [PilotAllocationProxy] })

  return {
    PilotAllocation: PilotAllocationProxy,
    PilotAllocationImplementation,
    PilotAllocationProxyAdmin,
  }
})

// Module for connecting to existing PilotAllocation deployment
export const MigratePilotAllocationModule = buildModule('PilotAllocationMigrate', (m) => {
  const pilotAllocationAddress = m.getParameter('pilotAllocationAddress')

  const PilotAllocation = m.contractAt('DirectAllocation', DirectAllocationArtifact, pilotAllocationAddress)

  return { PilotAllocation }
})
