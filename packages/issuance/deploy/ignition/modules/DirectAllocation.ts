import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import DirectAllocationArtifact from '../../../artifacts/contracts/allocate/DirectAllocation.sol/DirectAllocation.json'
import { deployImplementation } from './proxy/implementation'
import { deployWithTransparentUpgradeableProxy } from './proxy/TransparentUpgradeableProxy'

export default buildModule('DirectAllocation', (m) => {
  const governor = m.getAccount(1)
  const graphTokenAddress = m.getParameter('graphTokenAddress')

  // Deploy DirectAllocation implementation
  const DirectAllocationImplementation = deployImplementation(m, {
    name: 'DirectAllocation',
    artifact: DirectAllocationArtifact,
    constructorArgs: [graphTokenAddress],
  })

  // Deploy proxy
  const { proxy: DirectAllocationProxy, proxyAdmin: DirectAllocationProxyAdmin } =
    deployWithTransparentUpgradeableProxy(m, {
      name: 'DirectAllocation',
      artifact: DirectAllocationArtifact,
      constructorArgs: [graphTokenAddress],
      initArgs: [governor],
    })

  // Transfer ProxyAdmin ownership to governor
  m.call(DirectAllocationProxyAdmin, 'transferOwnership', [governor], { after: [DirectAllocationProxy] })

  return {
    DirectAllocation: DirectAllocationProxy,
    DirectAllocationImplementation,
    DirectAllocationProxyAdmin,
  }
})

// Module for connecting to existing DirectAllocation deployment
export const MigrateDirectAllocationModule = buildModule('DirectAllocationMigrate', (m) => {
  const directAllocationAddress = m.getParameter('directAllocationAddress')

  const DirectAllocation = m.contractAt('DirectAllocation', DirectAllocationArtifact, directAllocationAddress)

  return { DirectAllocation }
})

