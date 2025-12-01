import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import IssuanceAllocatorArtifact from '../../../artifacts/contracts/allocate/IssuanceAllocator.sol/IssuanceAllocator.json'
import GraphProxyAdmin2Module from './GraphProxyAdmin2'
import { deployWithGraphProxy } from './proxy/GraphProxy'

export default buildModule('IssuanceAllocator', (m) => {
  const governor = m.getAccount(1)
  const graphTokenAddress = m.getParameter('graphTokenAddress')

  // Use shared GraphProxyAdmin2
  const { GraphProxyAdmin2 } = m.useModule(GraphProxyAdmin2Module)

  // Deploy proxy using GraphProxy pattern with shared admin
  const { proxy: IssuanceAllocatorProxy, implementation: IssuanceAllocatorImplementation } = deployWithGraphProxy(
    m,
    GraphProxyAdmin2,
    {
      name: 'IssuanceAllocator',
      artifact: IssuanceAllocatorArtifact,
      constructorArgs: [graphTokenAddress],
      initArgs: [governor],
    },
  )

  return {
    IssuanceAllocator: IssuanceAllocatorProxy,
    IssuanceAllocatorImplementation,
  }
})

// Module for connecting to existing IssuanceAllocator deployment
export const MigrateIssuanceAllocatorModule = buildModule('IssuanceAllocatorMigrate', (m) => {
  const issuanceAllocatorAddress = m.getParameter('issuanceAllocatorAddress')

  const IssuanceAllocator = m.contractAt('IssuanceAllocator', IssuanceAllocatorArtifact, issuanceAllocatorAddress)

  return { IssuanceAllocator }
})
