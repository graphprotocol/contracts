import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import IssuanceAllocatorArtifact from '../../artifacts/contracts/allocate/IssuanceAllocator.sol/IssuanceAllocator.json'
import { deployImplementation } from './proxy/implementation'
import { deployWithTransparentUpgradeableProxy } from './proxy/TransparentUpgradeableProxy'

export default buildModule('IssuanceAllocator', (m) => {
  const governor = m.getAccount(1)
  const graphTokenAddress = m.getParameter('graphTokenAddress')

  // Deploy IssuanceAllocator implementation
  const IssuanceAllocatorImplementation = deployImplementation(m, {
    name: 'IssuanceAllocator',
    artifact: IssuanceAllocatorArtifact,
    constructorArgs: [graphTokenAddress],
  })

  // Deploy proxy
  const { proxy: IssuanceAllocatorProxy, proxyAdmin: IssuanceAllocatorProxyAdmin } =
    deployWithTransparentUpgradeableProxy(m, {
      name: 'IssuanceAllocator',
      artifact: IssuanceAllocatorArtifact,
      constructorArgs: [graphTokenAddress],
      initArgs: [governor],
    })

  // Transfer ProxyAdmin ownership to governor
  m.call(IssuanceAllocatorProxyAdmin, 'transferOwnership', [governor], { after: [IssuanceAllocatorProxy] })

  return {
    IssuanceAllocator: IssuanceAllocatorProxy,
    IssuanceAllocatorImplementation,
    IssuanceAllocatorProxyAdmin,
  }
})

// Module for connecting to existing IssuanceAllocator deployment
export const MigrateIssuanceAllocatorModule = buildModule('IssuanceAllocatorMigrate', (m) => {
  const issuanceAllocatorAddress = m.getParameter('issuanceAllocatorAddress')

  const IssuanceAllocator = m.contractAt('IssuanceAllocator', IssuanceAllocatorArtifact, issuanceAllocatorAddress)

  return { IssuanceAllocator }
})
