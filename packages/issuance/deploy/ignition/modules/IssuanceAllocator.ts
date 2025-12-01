import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import IssuanceAllocatorArtifact from '../../../artifacts/contracts/allocate/IssuanceAllocator.sol/IssuanceAllocator.json'
import { deployImplementation } from './proxy/implementation'
import { deployWithTransparentUpgradeableProxy } from './proxy/TransparentUpgradeableProxy'

export default buildModule('IssuanceAllocator', (m) => {
  const deployer = m.getAccount(0)
  const governor = m.getAccount(1)
  const graphTokenAddress = m.getParameter('graphTokenAddress')

  // Deploy proxy (this also deploys the implementation internally)
  const {
    proxy: IssuanceAllocatorProxy,
    proxyAdmin: IssuanceAllocatorProxyAdmin,
    implementation: IssuanceAllocatorImplementation,
  } = deployWithTransparentUpgradeableProxy(m, {
    name: 'IssuanceAllocator',
    artifact: IssuanceAllocatorArtifact,
    constructorArgs: [graphTokenAddress],
    initArgs: [governor],
  })

  // Transfer ProxyAdmin ownership to governor (must be called by deployer who owns it)
  m.call(IssuanceAllocatorProxyAdmin, 'transferOwnership', [governor], {
    from: deployer,
    after: [IssuanceAllocatorProxy],
  })

  return {
    IssuanceAllocator: IssuanceAllocatorProxy,
    IssuanceAllocatorProxyAdmin,
    IssuanceAllocatorImplementation,
  }
})

// Module for connecting to existing IssuanceAllocator deployment
export const MigrateIssuanceAllocatorModule = buildModule('IssuanceAllocatorMigrate', (m) => {
  const issuanceAllocatorAddress = m.getParameter('issuanceAllocatorAddress')

  const IssuanceAllocator = m.contractAt('IssuanceAllocator', IssuanceAllocatorArtifact, issuanceAllocatorAddress)

  return { IssuanceAllocator }
})

