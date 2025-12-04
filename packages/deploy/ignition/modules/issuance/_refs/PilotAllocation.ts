import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import DirectAllocationArtifact from '../../../../../issuance/artifacts/contracts/allocate/DirectAllocation.sol/DirectAllocation.json'

/**
 * Reference module for deployed PilotAllocation
 *
 * This module doesn't deploy anything - it just creates a reference to the
 * already-deployed PilotAllocation contract from the issuance package.
 *
 * Note: PilotAllocation is a proxy that uses DirectAllocation as its implementation.
 */
export default buildModule('PilotAllocationRef', (m) => {
  const address = m.getParameter('pilotAllocationAddress')

  const pilotAllocation = m.contractAt(
    'DirectAllocation',
    DirectAllocationArtifact,
    address,
    {
      id: 'PilotAllocation',
    },
  )

  return { pilotAllocation }
})
