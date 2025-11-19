import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import IssuanceAllocatorRef from './_refs/IssuanceAllocator'
import RewardsManagerRef from './_refs/RewardsManager'

export default buildModule('IssuanceAllocatorActive', (m) => {
  const { rewardsManager } = m.useModule(RewardsManagerRef)
  const { issuanceAllocator } = m.useModule(IssuanceAllocatorRef)

  const verifier = m.contractAt('IssuanceStateVerifier', '0x0000000000000000000000000000000000000000')
  m.call(verifier, 'assertIssuanceAllocatorSet', [rewardsManager, issuanceAllocator], { id: 'AssertIAIntegration' })

  return { rewardsManager, issuanceAllocator }
})
