import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import IssuanceAllocatorArtifact from '../../../../../issuance/artifacts/contracts/allocate/IssuanceAllocator.sol/IssuanceAllocator.json'

/**
 * Reference module for deployed IssuanceAllocator
 *
 * This module doesn't deploy anything - it just creates a reference to the
 * already-deployed IA contract from the issuance package.
 */
export default buildModule('IssuanceAllocatorRef', (m) => {
  const address = m.getParameter('issuanceAllocatorAddress')

  const issuanceAllocator = m.contractAt(
    'IssuanceAllocator',
    IssuanceAllocatorArtifact,
    address,
    {
      id: 'IssuanceAllocator',
    },
  )

  return { issuanceAllocator }
})
