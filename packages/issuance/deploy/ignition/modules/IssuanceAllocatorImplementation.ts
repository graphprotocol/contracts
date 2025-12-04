import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import IssuanceAllocatorArtifact from '../../../artifacts/contracts/allocate/IssuanceAllocator.sol/IssuanceAllocator.json'
import { deployImplementation } from './proxy/implementation'

/**
 * Deploy IssuanceAllocator implementation only (for upgrades)
 *
 * This module deploys a new IssuanceAllocator implementation contract without
 * deploying a proxy. It's used for upgrading an existing IssuanceAllocator proxy
 * to a new implementation via governance.
 *
 * Usage:
 *   npx hardhat ignition deploy ignition/modules/IssuanceAllocatorImplementation.ts \
 *     --parameters ignition/configs/issuance.arbitrumOne.json5 \
 *     --network arbitrumOne
 */
export default buildModule('IssuanceAllocatorImplementation', (m) => {
  const graphTokenAddress = m.getParameter('graphTokenAddress')

  const IssuanceAllocatorImplementation = deployImplementation(m, {
    name: 'IssuanceAllocator',
    artifact: IssuanceAllocatorArtifact,
    constructorArgs: [graphTokenAddress],
  })

  return { IssuanceAllocatorImplementation }
})
