import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import GraphTokenRef from './_refs/GraphToken'
import IssuanceAllocatorRef from './_refs/IssuanceAllocator'

export default buildModule('IssuanceAllocatorMinter', (m) => {
  const { graphToken } = m.useModule(GraphTokenRef)
  const { issuanceAllocator } = m.useModule(IssuanceAllocatorRef)

  const verifier = m.contractAt('IssuanceStateVerifier', '0x0000000000000000000000000000000000000000')
  m.call(verifier, 'assertMinterRole', [graphToken, issuanceAllocator], { id: 'AssertMinterRole' })

  return { graphToken, issuanceAllocator }
})
