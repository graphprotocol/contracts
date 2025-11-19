import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import DirectAllocationImplementationModule from '../contracts/DirectAllocationImplementation'
import GraphProxyAdmin2Module from '../contracts/GraphProxyAdmin2'

/**
 * Pilot Allocation Target
 *
 * Deploys a DirectAllocation proxy instance for the pilot allocation,
 * using the shared DirectAllocation implementation.
 * This is the 1% allocation contract for testing purposes.
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const PilotAllocationTarget: any = buildModule('PilotAllocation', (m) => {
  const owner = m.getParameter('owner')

  const { graphProxyAdmin2 } = m.useModule(GraphProxyAdmin2Module)
  const { implementation } = m.useModule(DirectAllocationImplementationModule)

  const initData = m.encodeFunctionCall(implementation, 'initialize', [owner])
  const pilotAllocation = m.contract('TransparentUpgradeableProxy', [implementation, graphProxyAdmin2, initData], {
    id: 'PilotAllocation',
  })

  return {
    pilotAllocation,
    pilotAllocationImpl: implementation,
  }
})

export default PilotAllocationTarget
