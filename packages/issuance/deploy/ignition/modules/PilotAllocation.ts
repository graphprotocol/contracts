import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import DirectAllocationArtifact from '../../../artifacts/contracts/allocate/DirectAllocation.sol/DirectAllocation.json'
import GraphProxyAdmin2Module from './GraphProxyAdmin2'
import { deployWithGraphProxy } from './proxy/GraphProxy'

export default buildModule('PilotAllocation', (m) => {
  const governor = m.getAccount(1)
  const graphTokenAddress = m.getParameter('graphTokenAddress')

  // Use shared GraphProxyAdmin2
  const { GraphProxyAdmin2 } = m.useModule(GraphProxyAdmin2Module)

  // Deploy proxy using GraphProxy pattern with shared admin
  // Note: The implementation contract is DirectAllocation.sol, but deployment is named PilotAllocation
  const { proxy: PilotAllocationProxy, implementation: PilotAllocationImplementation } = deployWithGraphProxy(
    m,
    GraphProxyAdmin2,
    {
      name: 'PilotAllocation',
      artifact: DirectAllocationArtifact,
      constructorArgs: [graphTokenAddress],
      initArgs: [governor],
    },
  )

  return {
    PilotAllocation: PilotAllocationProxy,
    PilotAllocationImplementation,
  }
})

// Module for connecting to existing PilotAllocation deployment
export const MigratePilotAllocationModule = buildModule('PilotAllocationMigrate', (m) => {
  const pilotAllocationAddress = m.getParameter('pilotAllocationAddress')

  const PilotAllocation = m.contractAt('DirectAllocation', DirectAllocationArtifact, pilotAllocationAddress)

  return { PilotAllocation }
})
